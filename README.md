# Miss Najwa's Learning Hub

أنشئ منصة تعليمية عربية حقيقية وقابلة للاستخدام باسم "Miss Najwa Ali" وفق المواصفات التالية. أريد Full-stack وليس mockup: Frontend + Backend + PostgreSQL/Supabase database + Supabase Auth + Storage + Row Level Security + RBAC + responsive RTL UI. استخدم React/TypeScript/Tailwind/shadcn بما يلائم Lovable.

- العربية بالكامل وRTL، Mobile-first وممتازة على الهاتف/التابلت/الكمبيوتر.
- الأدوار: Student وteacher_admin فقط. يوجد حسابان teacher_admin متساويان تماماً في الصلاحيات، مع usernames محددة من إعداد bootstrap الآمن. لا تضع أي كلمات مرور حقيقية في frontend أو source code؛ اجعل إنشاء حسابي المدرسين يتم server-side عبر secure bootstrap/secrets/env vars مع توثيق واضح، بحيث يمكن للمشغل إدخال كلمات المرور المطلوبة بأمان.
- صفحة ترحيب: "❤️ مرحباً بك في منصة Miss Najwa Ali" مع تسجيل الدخول وإنشاء حساب.
- تسجيل الطالب: الاسم الكامل، username أو وسيلة الدخول المناسبة، password، confirmation، اختيار مجموعة من المجموعات النشطة فقط، ثم access code خاص بالمجموعة. تحقق server-side من الكود ومن نشاط المجموعة.
- Groups: name, description, image, access_code، active/inactive. CRUD للإداريين، وتعطيل مفضل على الحذف. لا تحذف البيانات المرتبطة عشوائياً؛ safeguards/confirmation وقيود علاقات مناسبة.
- Student مرتبط بمجموعة واحدة حالياً. الإداري يستطيع نقل الطالب لمجموعة أخرى؛ بعد النقل يرى فقط بيانات المجموعة الجديدة، والواجبات السابقة لا تضيع.
- Student home: اسم المنصة، ترحيب باسم الطالب، مجموعته، أقرب حصة لمجموعته فقط، countdown حي كل ثانية، الانتقال تلقائياً للحصة التالية، وزر دخول الحصة يفتح meeting_url في تبويب جديد. إذا لا يوجد رابط: "رابط الحصة غير متاح حالياً".
- Classes: group_id, name, date, start_time, duration, meeting_url. CRUD للإداريين، جدول مع بحث/فلترة حسب المجموعة، وتعديل الرابط ينعكس للطلاب.
- Communities منفصلة لكل مجموعة: posts/comments/pinned. الطلاب يرون مجتمع مجموعتهم فقط ويمكنهم النشر/التعليق إذا الإعداد يسمح. الإداريان يستطيعان إنشاء/تعديل/حذف/تثبيت المنشورات، حذف التعليقات، إدارة الأعضاء، إزالة/نقل الطالب، ونشر الإعلانات.
- Assignments: الطالب يرفع صورة أو عدة صور JPG/JPEG/PNG/WEBP، معاينة، حذف/إضافة صور، عدد الصور، إرسال. تخزين حقيقي في Supabase Storage bucket خاص بسياسات وصول آمنة، MIME/type والحجم والامتداد validation ومنع الملفات الضارة. assignment يحتوي student/group/class/status/submitted_at وassignment_images. للمدرسين filters group/student/class/date/status، معرض صور zoom/navigation/download، حذف، وتجهيز واتساب.
- WhatsApp: رقم الإعدادات هو رقم الميس الذي سيحدده المشغل في Settings. جهز abstraction/integration point لـ WhatsApp Business Cloud API عند توافر credentials، ولا تدّع الإرسال الآلي دون API. fallback يفتح WhatsApp chat برسالة مُعبأة عن الواجب.
- Teacher dashboard/sidebar: الرئيسية، المجموعات، الطلاب، الحصص، الواجبات، المجتمعات، روابط الحصص، واتساب، الإعدادات، سجل العمليات، تسجيل الخروج. Cards للإحصاءات، أقرب الحصص، آخر الواجبات.
- Students CRUD/status enable-disable/transfer/view assignments.
- Settings: platform name/logo, WhatsApp number, image upload settings, community settings, student settings.
- ActivityLogs: login/logout, group CRUD/code changes, class CRUD/link changes, student CRUD/transfer, assignment upload/delete, post/delete, settings changes. Show user/action/date/time.
- Database relational schema: profiles/users, students, groups, classes, assignments, assignment_images, posts, comments, settings, activity_logs. Foreign keys, indexes, constraints.
- Security: backend authorization, RLS policies, students only read/write rows belonging to current group/current user as appropriate; teacher_admin manages all. Storage RLS so student cannot access another student's images. Validate URLs/uploads/forms. Never trust frontend. Avoid exposing access codes except authorized flows. Audit sensitive actions.
- Add loading/error/empty states, confirmations, Arabic toasts including: "أهلاً بك في منصة Miss Najwa Ali ❤️", "تم إنشاء حسابك بنجاح.", "تم تسجيلك في المجموعة بنجاح.", "الكود غير صحيح.", "هذه المجموعة غير متاحة حالياً.", "جاري رفع الواجب...", "تم إرسال الواجب بنجاح ❤️", "هل أنت متأكد من الحذف؟"
- Design calm modern educational, soft rounded cards, clear Arabic font, spacious, accessible contrast, keyboard support.
- No mock/demo behavior, no fake buttons, no hardcoded operational data, no local-only persistence. All real functionality uses backend/database/auth/storage.
- Create secure teacher bootstrap via server-side environment secrets, with two equal teacher_admin accounts identified by the requested usernames; document how to set their credentials securely without embedding them in code.
- Test signup/group code, login, group isolation, community isolation, class filtering/countdown/link changes, group CRUD/disable, transfer, assignment multi-image upload/storage, teacher management, both equal roles, and RLS/security. Fix issues found.
- Include concise README/setup docs for Supabase, auth bootstrap, storage policies, env vars, optional WhatsApp API, deployment.
- Inspect implementation before finishing and replace any remaining mock/demo behavior with real backend functionality.

This project was built with [Lovable](https://lovable.dev).

## Build with Lovable

Continue developing this project in the [Lovable editor](https://lovable.dev/projects/15a5d998-89d5-4718-bbc3-d3de6c42a2d9).

- **Ship faster**: describe what you want to build and Lovable handles the code.
- **Stay in sync**: every change made in Lovable is committed straight to this repository.
- **Full ownership**: this code is yours. Push to `main` on GitHub and your changes sync back into Lovable, ready for your next prompt.

## Development

Prefer working locally? You need Node.js and npm — [install with nvm](https://github.com/nvm-sh/nvm#installing-and-updating).

```sh
git clone <this-repository-url>
cd <repository-name>
npm i
npm run dev
```
