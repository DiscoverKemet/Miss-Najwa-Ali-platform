CREATE OR REPLACE FUNCTION public.validate_assignment_change() RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
DECLARE _is_teacher boolean := public.is_teacher(); _count integer; _max integer;
BEGIN
 IF NOT _is_teacher THEN
  IF TG_OP = 'UPDATE' THEN
   IF NEW.student_id IS DISTINCT FROM OLD.student_id OR NEW.group_id IS DISTINCT FROM OLD.group_id OR NEW.class_id IS DISTINCT FROM OLD.class_id OR NEW.notes IS DISTINCT FROM OLD.notes OR NEW.status IS DISTINCT FROM OLD.status OR OLD.submitted_at IS NOT NULL THEN RAISE EXCEPTION 'Assignment cannot be changed'; END IF;
   IF NEW.submitted_at IS DISTINCT FROM OLD.submitted_at THEN
    IF NEW.submitted_at IS NULL OR NEW.submitted_at > now() THEN RAISE EXCEPTION 'Invalid submission time'; END IF;
    SELECT count(*) INTO _count FROM public.assignment_images WHERE assignment_id = NEW.id;
    IF _count < 1 THEN RAISE EXCEPTION 'Upload at least one image'; END IF;
   END IF;
  ELSIF TG_OP = 'INSERT' AND (NEW.student_id <> auth.uid() OR NEW.group_id IS DISTINCT FROM public.my_group_id() OR NEW.status <> 'submitted' OR NEW.submitted_at IS NOT NULL) THEN RAISE EXCEPTION 'Invalid assignment'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER validate_assignment_before_write BEFORE INSERT OR UPDATE ON public.assignments FOR EACH ROW EXECUTE FUNCTION public.validate_assignment_change();
CREATE OR REPLACE FUNCTION public.validate_assignment_image() RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
DECLARE _owner uuid; _submitted timestamptz; _max integer; _mb integer; _count integer;
BEGIN
 SELECT student_id, submitted_at INTO _owner, _submitted FROM public.assignments WHERE id = NEW.assignment_id;
 IF NOT public.is_teacher() THEN
  IF _owner IS DISTINCT FROM auth.uid() OR _submitted IS NOT NULL OR split_part(NEW.storage_path, '/', 1) <> auth.uid()::text THEN RAISE EXCEPTION 'Invalid image ownership'; END IF;
  SELECT max_images_per_assignment, max_image_mb INTO _max, _mb FROM public.settings WHERE id = 1;
  SELECT count(*) INTO _count FROM public.assignment_images WHERE assignment_id = NEW.assignment_id;
  IF _count >= _max OR NEW.size_bytes > _mb * 1048576 THEN RAISE EXCEPTION 'Image limit exceeded'; END IF;
  IF NOT EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id = 'assignments' AND name = NEW.storage_path AND owner_id = auth.uid()::text) THEN RAISE EXCEPTION 'Image not uploaded'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER validate_assignment_image_before_insert BEFORE INSERT ON public.assignment_images FOR EACH ROW EXECUTE FUNCTION public.validate_assignment_image();
GRANT INSERT ON public.assignment_images TO authenticated;
CREATE POLICY "student adds own draft images" ON public.assignment_images FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM public.assignments a WHERE a.id = assignment_id AND a.student_id = auth.uid() AND a.submitted_at IS NULL) AND split_part(storage_path, '/', 1) = auth.uid()::text);
CREATE POLICY "student removes own draft images" ON public.assignment_images FOR DELETE TO authenticated USING (EXISTS (SELECT 1 FROM public.assignments a WHERE a.id = assignment_id AND a.student_id = auth.uid() AND a.submitted_at IS NULL));