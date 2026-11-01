CREATE TABLE public.contact_profiles (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  phone text,
  photo_path text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT contact_profiles_phone_check CHECK (phone IS NULL OR phone ~ '^\+?[0-9]{7,15}$'),
  CONSTRAINT contact_profiles_photo_path_check CHECK (photo_path IS NULL OR photo_path ~ '^[0-9a-f-]{36}/avatar\.(jpg|png|webp)$')
);

GRANT SELECT, INSERT, UPDATE ON public.contact_profiles TO authenticated;
GRANT ALL ON public.contact_profiles TO service_role;

ALTER TABLE public.contact_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own teachers read all teacher contacts visible"
ON public.contact_profiles FOR SELECT TO authenticated
USING (
  user_id = auth.uid()
  OR public.is_teacher()
  OR public.has_role(user_id, 'teacher_admin')
);

CREATE POLICY "Users insert own contact"
ON public.contact_profiles FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users update own contact"
ON public.contact_profiles FOR UPDATE TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE TRIGGER contact_profiles_touch_updated_at
BEFORE UPDATE ON public.contact_profiles
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

CREATE POLICY "Profile photos follow contact visibility"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'profile-photos'
  AND EXISTS (
    SELECT 1 FROM public.contact_profiles cp
    WHERE cp.photo_path = name
      AND (
        cp.user_id = auth.uid()
        OR public.is_teacher()
        OR public.has_role(cp.user_id, 'teacher_admin')
      )
  )
);

CREATE POLICY "Users upload own profile photo"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'profile-photos'
  AND (storage.foldername(name))[1] = auth.uid()::text
  AND name ~ ('^' || auth.uid()::text || '/avatar\.(jpg|png|webp)$')
);

CREATE POLICY "Users replace own profile photo"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'profile-photos'
  AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
  bucket_id = 'profile-photos'
  AND (storage.foldername(name))[1] = auth.uid()::text
  AND name ~ ('^' || auth.uid()::text || '/avatar\.(jpg|png|webp)$')
);

CREATE POLICY "Users delete own profile photo"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'profile-photos'
  AND (storage.foldername(name))[1] = auth.uid()::text
);