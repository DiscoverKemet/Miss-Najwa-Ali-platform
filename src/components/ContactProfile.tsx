import { useEffect, useState } from 'react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Phone, Upload } from 'lucide-react';
import type { Tables } from '@/integrations/supabase/types';

type Contact = Tables<'contact_profiles'>;
type Profile = Tables<'profiles'>;
const TYPES: Record<string, string> = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };

export function ContactProfile({ userId, teacher, profiles }: { userId: string; teacher: boolean; profiles: Profile[] }) {
  const [rows, setRows] = useState<Contact[]>([]);
  const [urls, setUrls] = useState<Record<string, string>>({});
  const [phone, setPhone] = useState('');
  const [busy, setBusy] = useState(false);

  async function load() {
    const { data } = await supabase.from('contact_profiles').select('*');
    const list = data ?? [];
    setRows(list);
    setPhone(list.find((r) => r.user_id === userId)?.phone ?? '');
    const paths = list.map((r) => r.photo_path).filter(Boolean) as string[];
    if (paths.length) {
      const { data: signed } = await supabase.storage.from('profile-photos').createSignedUrls(paths, 3600);
      const m: Record<string, string> = {};
      signed?.forEach((s) => { if (s.path && s.signedUrl) m[s.path] = s.signedUrl; });
      setUrls(m);
    }
  }
  useEffect(() => { void load(); }, [userId]);

  const mine = rows.find((r) => r.user_id === userId);

  async function save(photo?: string) {
    const clean = phone.replace(/[\s-]/g, '');
    if (clean && !/^\+?[0-9]{7,15}$/.test(clean)) { toast.error('اكتب رقم صحيح (أرقام فقط من 7 إلى 15)'); return false; }
    const { error } = await supabase.from('contact_profiles').upsert({ user_id: userId, phone: clean || null, photo_path: photo ?? mine?.photo_path ?? null });
    if (error) { toast.error('تعذّر حفظ البيانات'); return false; }
    return true;
  }

  async function upload(f: File): Promise<void> {
    const ext = TYPES[f.type];
    if (!ext) { toast.error('الصورة لازم تكون JPG أو PNG أو WEBP'); return; }
    if (f.size > 5 * 1024 * 1024) { toast.error('حجم الصورة أكبر من 5 ميجا'); return; }
    setBusy(true);
    const path = `${userId}/avatar.${ext}`;
    const { error } = await supabase.storage.from('profile-photos').upload(path, f, { upsert: true, contentType: f.type });
    if (error) { setBusy(false); toast.error('تعذّر رفع الصورة'); return; }
    if (await save(path)) toast.success('تم حفظ صورتك');
    await load(); setBusy(false);
  }

  const person = (r: Contact) => {
    const p = profiles.find((x) => x.id === r.user_id);
    return (
      <div key={r.user_id} className="list-row">
        {r.photo_path && urls[r.photo_path] ? <img src={urls[r.photo_path]} alt="" className="avatar" style={{ objectFit: 'cover' }} /> : <span className="avatar">{p?.full_name?.slice(0, 1) ?? 'م'}</span>}
        <div className="grow"><strong>{p?.full_name ?? 'مستخدم'}</strong>{r.phone ? <small><a href={`tel:${r.phone}`} dir="ltr">{r.phone}</a></small> : <small>لا يوجد رقم</small>}</div>
        {r.phone && <Button asChild size="sm" variant="outline"><a href={`tel:${r.phone}`}><Phone /> اتصال</a></Button>}
      </div>
    );
  };
  const others = rows.filter((r) => r.user_id !== userId);

  return (
    <div className="stack">
      <div className="form-band">
        <h3>صورتي ورقمي</h3>
        <p className="text-muted-foreground">{teacher ? 'صورتك ورقمك يظهروا لكل الطلاب.' : 'صورتك ورقمك يظهروا للمعلمة فقط.'}</p>
        <div className="list-row">
          {mine?.photo_path && urls[mine.photo_path] ? <img src={urls[mine.photo_path]} alt="صورتي" className="avatar" style={{ objectFit: 'cover', width: 72, height: 72 }} /> : <span className="avatar">؟</span>}
          <label className="grow"><Button asChild variant="outline" disabled={busy}><span><Upload /> {busy ? 'جاري الرفع…' : 'اختيار صورة'}</span></Button><input type="file" hidden accept="image/jpeg,image/png,image/webp" onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(f); e.target.value = ''; }} /></label>
        </div>
        <form className="editor" onSubmit={async (e) => { e.preventDefault(); setBusy(true); if (await save()) toast.success('تم حفظ رقمك'); await load(); setBusy(false); }}>
          <Input dir="ltr" inputMode="tel" placeholder="01xxxxxxxxx" value={phone} onChange={(e) => setPhone(e.target.value)} maxLength={20} />
          <Button disabled={busy}>حفظ الرقم</Button>
        </form>
      </div>
      <div className="form-band">
        <h3>{teacher ? 'بيانات الطلاب' : 'تواصل مع المعلمة'}</h3>
        {others.length ? others.map(person) : <p className="empty">لا توجد بيانات بعد</p>}
      </div>
    </div>
  );
}
