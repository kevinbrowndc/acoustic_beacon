export class Api {
  constructor(base, timeout = 10000) { this.base = base; this.timeout = timeout; this.csrf = ''; }
  async request(path, {method = 'GET', body, headers = {}} = {}) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeout);
    try {
      const response = await fetch(`${this.base}/api/v1/dashboard${path}`, {
        method, credentials: 'include', cache: 'no-store', signal: controller.signal,
        headers: {Accept:'application/json', ...(body ? {'Content-Type':'application/json'} : {}),
          ...(method !== 'GET' ? {'X-CSRF-Token':this.csrf} : {}), ...headers},
        ...(body ? {body:JSON.stringify(body)} : {})
      });
      const json = await response.json();
      if (!response.ok) {
        const message = Array.isArray(json.detail) ? json.detail.map(e => `${e.loc?.at(-1) || 'Value'}: ${e.msg}`).join('. ') : json.detail;
        const error = new Error(typeof message === 'string' ? message : 'The request could not be completed.');
        error.status = response.status; throw error;
      }
      if (json.csrf_token) this.csrf = json.csrf_token;
      return json;
    } catch (error) {
      if (error.name === 'AbortError') throw new Error('The server took too long to respond. Please try again.');
      if (error instanceof TypeError) throw new Error('Cannot reach your backend. Check the connection and try again.');
      throw error;
    } finally { clearTimeout(timer); }
  }
}
