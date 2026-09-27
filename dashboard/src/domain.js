export const routes = ['dashboard', 'offers', 'campaigns', 'beacon', 'activity', 'account'];
export const escapeHtml = (value = '') => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function resolveApiBase(value, production, origin) {
  const url = new URL(value || origin);
  const local = ['localhost','127.0.0.1','[::1]','10.0.2.2'].includes(url.hostname) || url.hostname.endsWith('.localhost');
  if (url.username || url.password || url.search || url.hash || url.pathname !== '/' ||
      (production && (url.protocol !== 'https:' || local)) ||
      (!production && url.protocol !== 'https:' && !(url.protocol === 'http:' && local))) {
    throw new Error('The API address must be a public HTTPS origin, or local HTTP during development.');
  }
  return url.origin;
}
export function statusOf(item, now = new Date()) {
  if (!item.active) return 'inactive';
  if (item.end_at && new Date(item.end_at) <= now) return 'expired';
  if (item.start_at && new Date(item.start_at) > now) return 'scheduled';
  return 'active';
}
export function offerPayload(offer) {
  return Object.fromEntries(['title','description','terms','image_url','start_at','end_at','active','manager_eligible'].map(k => [k, offer[k] ?? null]));
}
export const routeFromHash = hash => hash.replace(/^#\/?/, '') || 'dashboard';
export const localDate = value => {
  if (!value) return '';
  const date = new Date(value);
  return new Date(date.getTime() - date.getTimezoneOffset() * 60000).toISOString().slice(0,16);
};
export const dateToApi = value => value ? new Date(value).toISOString() : null;
export const safeImage = value => {
  try { const u = new URL(value); return u.protocol === 'https:' && !u.username && !u.password ? u.href : null; } catch { return null; }
};
