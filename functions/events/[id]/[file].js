import {calendarResponse} from '../../../lib/public-events.mjs';
export const onRequestGet = ({request,params}) => calendarResponse(request, params.id, params.file);
