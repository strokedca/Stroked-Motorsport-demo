# Donation, Information and free administrator promotions

The header retains the original logo and tagline. Its compact buttons are **Donation** and **Information**. Changing the Donation label does not change the tax settings or activate payment collection.

## Owner workflow

Sign in with the existing administrator account and choose **Add promotion** in the account bar, or open **My account** and use **Site promotions — administrator**.

- Link an approved event or create a separate local event, charity event or community announcement.
- Choose **Featured Event**, **Enhanced Event Page** and **Sponsor Spotlight** in any combination. All three are free when an administrator creates the promotion. This workflow never calls Stripe or requires checkout.
- Add a cover/poster, up to six gallery images, and optional sponsor name, logo and website. Gallery and sponsor presentation follow the selected options.
- Set the start and optional end date, then publish. Edit, hide or republish existing promotions from the same dashboard.
- A linked featured event receives a badge and priority among the currently relevant event-list results. Gallery and sponsor content also appear in the linked event details.
- The copyable local-business sales pitch is in the same administrator section. It describes current free listings and promotion packages being finalized; it makes no audience-size or paid-checkout claims.

## Visitor guidance

**Information** explains the calendar and filters, Going and Interested RSVPs, saving/updating/removing responses, free organizer accounts, event submissions and approval, event changes, promotion options, donations and public contact information. It includes buttons to open the corresponding site sections. Administrators additionally see the free promotion instructions.

## Data and permissions

`20261112002003_admin_site_promotions.sql` adds a private, RLS-enabled promotion table, fixed production/testing RPC wrappers and a public image bucket limited to JPEG/PNG/WebP files of 5 MB each. Only verified administrators for the corresponding environment may write promotion records or upload files. Ordinary users cannot publish or edit promotions, and testing administrator authority does not grant production authority.

The public RPC exposes only active promotions within their date range. Linked events must be approved. Editing and hiding persist across devices. No demo promotions are seeded. Validation records are rolled back rather than left on the public site.

The existing events, profiles, pending changes, RSVPs, administrator membership and payment settings are preserved. Donation checkout and public paid promotion prices remain separately unconfigured.

## Validation

Fifteen automated checks passed, covering current account/RSVP workflows, free promotion publishing, database and storage authorization, linked event upgrades, date visibility, safe rendering and help-button navigation. Browser checks covered the three admin choices, saving without checkout, the copyable sales pitch and the Information dialog. Hosted RPC checks passed inside a rolled-back transaction; no sample promotion was committed. Existing live event records retained their previous fingerprint.

## Paid bookings and poster files

Paid bookings appear separately under **Promotion payments & bookings**. Select **Prepare paid promotion** only after Stripe confirms payment, add the approved artwork and check the full campaign dates. Publishing that booking records its placement without taking another payment. The existing **Add promotion** workflow remains free for the site owner.

Poster uploads accept **JPEG, PNG or WebP up to 5 MB**. Convert a PDF poster to an image before selecting it. Download chat attachments to the computer first, then use the file chooser.
