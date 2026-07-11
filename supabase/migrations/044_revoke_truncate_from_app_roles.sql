REVOKE TRUNCATE ON TABLE public.centers FROM PUBLIC;
REVOKE TRUNCATE ON TABLE public.center_media FROM PUBLIC;
REVOKE TRUNCATE ON TABLE public.admissions FROM PUBLIC;
REVOKE TRUNCATE ON TABLE public.consultations FROM PUBLIC;

REVOKE TRUNCATE ON TABLE public.centers FROM anon;
REVOKE TRUNCATE ON TABLE public.center_media FROM anon;
REVOKE TRUNCATE ON TABLE public.admissions FROM anon;
REVOKE TRUNCATE ON TABLE public.consultations FROM anon;

REVOKE TRUNCATE ON TABLE public.centers FROM authenticated;
REVOKE TRUNCATE ON TABLE public.center_media FROM authenticated;
REVOKE TRUNCATE ON TABLE public.admissions FROM authenticated;
REVOKE TRUNCATE ON TABLE public.consultations FROM authenticated;
