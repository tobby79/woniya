// .env.local의 VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY 값을 그대로 옮겨 적으세요.
// 이 파일은 빌드 도구(Vite 등) 없이 정적 HTML이 바로 읽도록 만든 런타임 설정입니다.
// anon key는 RLS로 보호되는 공개 키라 노출돼도 안전합니다 (service_role 키는 절대 넣지 마세요).
window.__SUPABASE_CONFIG__ = {
  url: 'https://ovlutsjripievdyryopn.supabase.co',
  anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im92bHV0c2pyaXBpZXZkeXJ5b3BuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIxNTUzNDYsImV4cCI6MjA5NzczMTM0Nn0.A3LEKa7ugCmSA3_jfzps8BW1XcBV9dBv-PpgF5wMdqE'
};
