import {test} from 'node:test';
import assert from 'node:assert/strict';
import {eventResponse, eventIcs, calendarResponse} from '../lib/public-events.mjs';
const id = '12345678-1234-4234-8234-123456789012';
const base = {name:'Game Rally, Club VTT', club:'Club', date:'2099-01-16', time:'13:00', city:'Brantville', province:'New Brunswick', startLocation:'Parish Hall; Brantville', details:'Bring a helmet', status:'Scheduled', categories:['ATVs / Off-road']};
const fetcher = payload => async () => Response.json([{id, payload}]);

test('event page offers Google and .ics calendar links for upcoming events only', async () => {
  const html = await (await eventResponse(new Request('https://stroked.ca/events/'+id+'/'), id, fetcher(base))).text();
  assert.match(html, /Add to calendar:/);
  assert.match(html, /calendar\.google\.com\/calendar\/render\?action=TEMPLATE/);
  assert.match(html, /dates=20990116T130000%2F20990116T150000/);
  assert.match(html, /ctz=America%2FHalifax/);
  assert.match(html, new RegExp('href="/events/'+id+'/calendar\\.ics" download'));
  for (const payload of [{...base, status:'Cancelled'}, {...base, date:'2001-01-01'}]) {
    const other = await (await eventResponse(new Request('https://stroked.ca/events/'+id+'/'), id, fetcher(payload))).text();
    assert.doesNotMatch(other, /Add to calendar/);
  }
});

test('calendar=ics returns a valid timed or all-day event', async () => {
  const response = await eventResponse(new Request('https://stroked.ca/events/'+id+'/?calendar=ics'), id, fetcher(base));
  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-type'), /^text\/calendar/);
  assert.match(response.headers.get('content-disposition'), /attachment/);
  const ics = await response.text();
  assert.match(ics, /^BEGIN:VCALENDAR\r\n/);
  assert.match(ics, /DTSTART;TZID=America\/Halifax:20990116T130000\r\n/);
  assert.match(ics, /DTEND;TZID=America\/Halifax:20990116T150000\r\n/);
  assert.match(ics, /SUMMARY:Game Rally\\, Club VTT\r\n/);
  assert.match(ics, new RegExp('UID:'+id+'@stroked.ca'));
  for (const line of ics.split('\r\n')) assert.ok(line.length <= 75, line);
  const multi = eventIcs(id, {...base, time:'', endDate:'2099-01-18', province:'British Columbia'});
  assert.match(multi, /DTSTART;VALUE=DATE:20990116\r\n/);
  assert.match(multi, /DTEND;VALUE=DATE:20990119\r\n/);
  const nl = eventIcs(id, {...base, province:'Newfoundland and Labrador'});
  assert.match(nl, /TZID=America\/St_Johns/);
  const late = eventIcs(id, {...base, time:'23:00'});
  assert.match(late, /DTEND;TZID=America\/Halifax:20990117T010000/);
});

test('calendar.ics path returns the file and rejects other names', async () => {
  const ok = await calendarResponse(new Request('https://stroked.ca/events/'+id+'/calendar.ics'), id, 'calendar.ics', fetcher(base));
  assert.equal(ok.status, 200);
  assert.match(ok.headers.get('content-type'), /^text\/calendar/);
  assert.match(await ok.text(), /^BEGIN:VCALENDAR/);
  assert.equal((await calendarResponse(new Request('https://stroked.ca/events/'+id+'/x'), id, 'x', fetcher(base))).status, 404);
});
