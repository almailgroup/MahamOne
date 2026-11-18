import type { Dictionary } from '../index';

/**
 * Warehouses and items issued to employees: the main warehouse and its
 * sub-warehouses (مستودع فرعي), who looks after each, sending stock to them,
 * and issuing uniforms and other items (صرف مواد) that an approver confirms.
 */
export default {
  'Issued {items} to {name}, waiting for approval': 'صرف {items} إلى {name}، بانتظار الاعتماد',
  'Confirmed the items issued to {name}: {items}': 'أكّد المواد المصروفة إلى {name}: {items}',
  'Turned down the items to issue to {name}: {items}': 'رفض صرف المواد إلى {name}: {items}',
  'Took back the items to issue to {name}: {items}': 'سحب طلب صرف المواد إلى {name}: {items}',
  'Recorded {items} issued to {name}': 'سجّل صرف {items} إلى {name}',
  'Items issued': 'مواد مصروفة',
  'New sub-warehouse': 'مستودع فرعي جديد',
  'Stock reaches it from the main warehouse, and whoever looks after it issues items from it.':
    'يصله المخزون من المستودع الرئيسي، ويصرف منه المواد المسؤولُ عنه.',
  'A sub-warehouse gets its stock from its main warehouse.':
    'يحصل المستودع الفرعي على مخزونه من المستودع الرئيسي التابع له.',
  'Nothing: it is a main warehouse': 'لا شيء: هذا مستودع رئيسي',
  'Looked after by': 'المسؤول عنه',
  'The employee responsible for the stock kept here.': 'الموظف المسؤول عن المخزون المحفوظ هنا.',
  Nobody: 'لا أحد',
  'e.g. Ahmed’s store': 'مثال: مستودع أحمد',
  'Issues items from it': 'يصرف المواد منه',
  'The Maham One account that issues items to employees from this sub-warehouse. Each issue waits for an approver.':
    'حساب مهام ون الذي يصرف المواد للموظفين من هذا المستودع الفرعي. كل صرف ينتظر اعتماد معتمِد.',
  'Nobody: only the owner, admins and accountants issue':
    'لا أحد: يصرف المالك والمشرفون والمحاسبون فقط',
  'Issued items': 'المواد المصروفة',
  'You look after {warehouse}': 'أنت مسؤول عن {warehouse}',
  'Issue uniforms and other items from it to employees. Each issue waits for an approver.':
    'اصرف منه الزي الرسمي والمواد الأخرى للموظفين. كل صرف ينتظر اعتماد معتمِد.',
  'Issue items': 'صرف مواد',
  'Main warehouse': 'المستودع الرئيسي',
  'Sub-warehouse': 'مستودع فرعي',
  'Looked after by {name}': 'المسؤول عنه {name}',
  'Send stock': 'إرسال مخزون',
  'Add a sub-warehouse': 'إضافة مستودع فرعي',
  'Choose the employee who receives the items.': 'اختر الموظف الذي يستلم المواد.',
  'Sent for approval. The stock leaves the warehouse once it is confirmed.':
    'أُرسل للاعتماد. يخرج المخزون من المستودع بعد تأكيده.',
  'Hand uniforms and other items to an employee. The stock leaves the warehouse at once.':
    'سلّم الزي الرسمي والمواد الأخرى لموظف. يخرج المخزون من المستودع فوراً.',
  'Hand uniforms and other items to an employee. An approver confirms it, then the stock leaves your warehouse.':
    'سلّم الزي الرسمي والمواد الأخرى لموظف. يؤكده معتمِد، ثم يخرج المخزون من مستودعك.',
  'There is no warehouse you can issue items from': 'لا يوجد مستودع يمكنك الصرف منه',
  'The owner, an admin or an accountant sets up sub-warehouses and who issues items from them.':
    'يُنشئ المالك أو المشرف أو المحاسب المستودعات الفرعية ويحدد من يصرف منها.',
  'Issuing items needs the latest database update. Ask the owner to run it.':
    'صرف المواد يحتاج إلى آخر تحديث لقاعدة البيانات. اطلب من المالك تشغيله.',
  'Issued to': 'صُرفت إلى',
  '{quantity} left in {warehouse}': 'المتبقي {quantity} في {warehouse}',
  'Only {quantity} left to issue.': 'المتبقي للصرف {quantity} فقط.',
  'Add an item': 'إضافة صنف',
  'e.g. New joiner, replacement for a torn jacket': 'مثال: موظف جديد، بدل سترة ممزقة',
  'Not found': 'غير موجود',
  'These items issued are not on this device.': 'هذه المواد المصروفة غير موجودة على هذا الجهاز.',
  'The items stay on record as void, their stock comes back to the warehouse and their cost leaves the books.':
    'تبقى المواد مسجلة كملغاة، ويعود مخزونها إلى المستودع وتخرج تكلفتها من الدفاتر.',
  'Items issued {number}': 'صرف مواد {number}',
  'Items to issue': 'مواد للصرف',
  'Voided on {date}': 'أُلغي في {date}',
  'Confirmed by': 'أكّده',
  '{name} · {date}': '{name} · {date}',
  'Stock of {warehouse}:': 'مخزون {warehouse}:',
  'Uniforms and other items handed to employees, and who confirmed them.':
    'الزي الرسمي والمواد الأخرى المسلّمة للموظفين، ومن أكّدها.',
  'Void or rejected': 'ملغاة أو مرفوضة',
  'Search employees or items…': 'ابحث في الموظفين أو الأصناف…',
  'Search employees or items': 'ابحث في الموظفين أو الأصناف',
  'No items issued yet': 'لم تُصرف أي مواد بعد',
  'Uniforms, shoes and badges handed to employees show here, with who issued them and who confirmed them.':
    'يظهر هنا الزي الرسمي والأحذية والشارات المسلّمة للموظفين، مع من صرفها ومن أكّدها.',
  'All employees': 'كل الموظفين',
  'All items': 'كل الأصناف',
  'No items issued': 'لا توجد مواد مصروفة',
  'Items issued to employees and confirmed show here, line by line.':
    'تظهر هنا المواد المصروفة للموظفين والمؤكدة، بنداً بنداً.',
  'Items issued are voided, never deleted.': 'المواد المصروفة تُلغى ولا تُحذف أبداً.',
  'Only an approver records items issued. Send them for approval instead.':
    'المعتمِد وحده يسجّل صرف المواد. أرسلها للاعتماد بدلاً من ذلك.',
  'You can only issue items from the sub-warehouse you look after.':
    'لا يمكنك الصرف إلا من المستودع الفرعي الذي أنت مسؤول عنه.',
  'Only the owner, an admin or an accountant sets up sub-warehouses or changes their stock directly.':
    'المالك أو المشرف أو المحاسب وحده يُنشئ المستودعات الفرعية أو يغيّر مخزونها مباشرة.',
  'Items to issue to {name} sent for approval': 'أُرسل صرف مواد إلى {name} للاعتماد',
  'Request to issue items to {name} cancelled': 'أُلغي طلب صرف مواد إلى {name}',
  'Items issued to {name} confirmed': 'تأكّد صرف المواد إلى {name}',
  'Items to issue to {name} not confirmed': 'لم يُؤكَّد صرف المواد إلى {name}',
  'Request to issue items to {name} expired': 'انتهت صلاحية طلب صرف مواد إلى {name}',
  'Choose the main warehouse this one belongs to.':
    'اختر المستودع الرئيسي الذي يتبعه هذا المستودع.',
  'A sub-warehouse can’t have sub-warehouses of its own.':
    'لا يمكن أن يكون للمستودع الفرعي مستودعات فرعية خاصة به.',
  'This warehouse has sub-warehouses, so it can’t become a sub-warehouse.':
    'لهذا المستودع مستودعات فرعية، فلا يمكن أن يصبح مستودعاً فرعياً.',
  'A sub-warehouse can’t be the default warehouse.':
    'لا يمكن أن يكون المستودع الفرعي هو المستودع الافتراضي.',
  'Archive its sub-warehouses before archiving this warehouse.':
    'أرشف مستودعاته الفرعية قبل أرشفة هذا المستودع.',
  'Choose the warehouse the items come from.': 'اختر المستودع الذي تُصرف منه المواد.',
  'Only stock items can be issued.': 'لا يمكن صرف إلا الأصناف المخزنية.',
  'Only {quantity} of {item} left in {warehouse} to issue.':
    'المتبقي للصرف من {item} في {warehouse} هو {quantity} فقط.',
  'Items issued to {name}: {items}': 'مواد مصروفة إلى {name}: {items}',
  'Items issued {number} voided': 'أُلغي صرف المواد {number}',
  'Items to issue to {name} sent for approval: {items}':
    'أُرسل صرف مواد إلى {name} للاعتماد: {items}',
  '{warehouse} has only {quantity} of {item} left.':
    'لم يتبقَّ في {warehouse} من {item} إلا {quantity}.',
  'Only an approver voids items issued.': 'المعتمِد وحده يلغي صرف المواد.',
  '{issuer} issued to {name}:': 'صرف {issuer} إلى {name}:',
  'Confirming it takes the stock below zero; send more stock to the warehouse first.':
    'تأكيده ينزل بالمخزون تحت الصفر؛ أرسل مخزوناً إضافياً إلى المستودع أولاً.',
  'Confirmed: the items are issued': 'تم التأكيد: صُرفت المواد',
  'Reject these items?': 'رفض صرف هذه المواد؟',
  'Nothing leaves the warehouse. Whoever asked sees why.':
    'لا يخرج شيء من المستودع. ويرى صاحب الطلب السبب.',
  'Connect to the internet to see who items can be issued to.':
    'اتصل بالإنترنت لترى من يمكن الصرف لهم.',
  'Uniforms and other items issued to this employee show here.':
    'يظهر هنا الزي الرسمي والمواد الأخرى المصروفة لهذا الموظف.',
  'Items held': 'المواد التي في عهدته',
  'Everything issued to them and confirmed, item by item.': 'كل ما صُرف له وتأكّد، صنفاً صنفاً.',
  'Nothing confirmed yet.': 'لم يتأكد شيء بعد.',
  'Items to an employee': 'مواد لموظف',
  'Issue items to an employee': 'صرف مواد لموظف',
  'No account is set up for items issued to employees.':
    'لا يوجد حساب معدّ للمواد المصروفة للموظفين.',
  'Items issued {number} to {name}': 'صرف مواد {number} إلى {name}',
  'These items are already on record under another request. Reject this one.':
    'هذه المواد مسجلة بالفعل بطلب آخر. ارفض هذا الطلب.',
} satisfies Dictionary;
