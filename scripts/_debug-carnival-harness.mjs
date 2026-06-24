import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(__dirname, '..');
const cfgText = readFileSync(path.join(projectRoot, 'supabase-config.js'), 'utf8');
const url = cfgText.match(/url:\s*'([^']+)'/)[1];
const anonKey = cfgText.match(/anonKey:\s*'([^']+)'/)[1];

const captured = {}; // id -> last innerHTML set

function makeEl(id) {
  return {
    _id: id,
    set innerHTML(v) { captured[id] = v; },
    get innerHTML() { return captured[id] || ''; },
    classList: { add(){}, remove(){}, toggle(){}, contains(){return false;} },
    addEventListener(){},
    setAttribute(){},
    getAttribute(){return null;},
    querySelector(){return null;},
    querySelectorAll(){return [];},
    appendChild(){},
    style: {},
  };
}

function authHeaders(extra={}) { return { apikey: anonKey, Authorization: 'Bearer ' + anonKey, ...extra }; }

const fakeSupabase = {
  createClient(_url, _key) {
    return {
      from(table) {
        const state = { table, filters: [], selectStr: '*' };
        const builder = {
          select(s) { state.selectStr = s; return builder; },
          eq(col, val) { state.filters.push([col, val]); return builder; },
          async single() {
            const qs = new URLSearchParams();
            qs.set('select', state.selectStr);
            for (const [c,v] of state.filters) qs.set(c, 'eq.' + v);
            const res = await fetch(`${url}/rest/v1/${table}?${qs.toString()}`, { headers: authHeaders() });
            const arr = await res.json();
            if (!res.ok) return { data: null, error: arr };
            return { data: arr[0] || null, error: arr[0] ? null : { message: 'no rows' } };
          },
        };
        return builder;
      },
      storage: {
        from(bucket) {
          return {
            async createSignedUrl(p, expiresIn) {
              const res = await fetch(`${url}/storage/v1/object/sign/${bucket}/${p}`, {
                method: 'POST',
                headers: { ...authHeaders(), 'content-type': 'application/json' },
                body: JSON.stringify({ expiresIn }),
              });
              if (!res.ok) return { data: null, error: await res.text() };
              const j = await res.json();
              return { data: { signedUrl: url + '/storage/v1' + j.signedURL }, error: null };
            },
          };
        },
      },
    };
  },
};

const sandbox = {
  console,
  fetch,
  window: { __SUPABASE_CONFIG__: { url, anonKey }, matchMedia: () => ({ matches: false }) },
  document: {
    getElementById: (id) => makeEl(id),
    querySelectorAll: () => [],
    addEventListener: () => {},
    documentElement: { setAttribute(){}, removeAttribute(){} },
    title: '',
  },
  location: { search: '?slug=soop' },
  URLSearchParams,
  supabase: fakeSupabase,
  WoniyaTopbar: { init: (opts) => console.log('[harness] WoniyaTopbar.init called with', JSON.stringify(opts)) },
  IntersectionObserver: class { observe(){} unobserve(){} },
  setTimeout, clearTimeout, Promise,
};
sandbox.globalThis = sandbox;

vm.createContext(sandbox);

const scriptBody = readFileSync('C:/Users/user/AppData/Local/Temp/claude/e--------woniya/e0681588-3c2f-4f43-b52f-93ce46565396/scratchpad/carnival_script.js', 'utf8');

process.on('unhandledRejection', (err) => {
  console.error('[harness] UNHANDLED REJECTION:', err && err.stack || err);
});

try {
  vm.runInContext(scriptBody, sandbox, { filename: 'template-carnival-inline.js' });
} catch (e) {
  console.error('[harness] SYNCHRONOUS THROW:', e.stack || e);
}

setTimeout(() => {
  console.log('\n=== captured innerHTML keys ===');
  console.log(Object.keys(captured));
  console.log('\n=== photozone snippet ===');
  console.log((captured.photozone || '(not set)').slice(0, 600));
  console.log('\n=== staff snippet ===');
  console.log((captured.staff || '(not set)').slice(0, 600));
  console.log('\n=== greeting snippet ===');
  console.log((captured.greeting || '(not set)').slice(0, 600));
}, 12000);
