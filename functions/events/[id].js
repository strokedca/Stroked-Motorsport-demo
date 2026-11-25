import {eventResponse} from '../../lib/public-events.mjs';
export const onRequestGet = ({request,params}) => eventResponse(request, params.id);
