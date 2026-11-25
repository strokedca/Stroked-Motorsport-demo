import {sitemapResponse} from '../lib/public-events.mjs';
export const onRequestGet = ({request}) => sitemapResponse(request);
