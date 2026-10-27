import { db } from '../db';
import { clearCheque } from '../cheques';
import { saveLandedCost } from '../inventory';
import { createAsset, saveAsset } from '../assets';
import type { ISODate, InvoiceDocument, Payment } from '../types';
import { addDaysISO } from '@/lib/dates';
import { round } from '@/lib/money';
import type { DemoBooks } from './books';
import type { Timeline } from './calendar';
import { both, VENDORS, type ItemKey } from './data';
import { nextWorkday } from './sales';

export function purchasesStory(books: DemoBooks, tl: Timeline): void {
  imports(books, tl);
  security(books, tl);
  cables(books, tl);
  subcontractor(books, tl);
  computers(books, tl);
}

/* -------------------------------------------------------------------------- */
/* Imports: LED lighting from China (USD), security systems from Dubai (AED)   */
/* -------------------------------------------------------------------------- */

interface Shipment {
  order: number;
  arrived: number;
  goods: [ItemKey, number, number][];
  rates: { order: number; bill: number; paid: number };
  reference: string;
  freight: number;
  clearing: number;
}

/** Two sea shipments a year from Shenzhen. */
const SHIPMENTS: Shipment[] = [
  {
    order: -12,
    arrived: -11,
    goods: [
      ['panel', 700, 10.2],
      ['downlight', 1800, 3.15],
      ['flood', 70, 22.5],
    ],
    rates: { order: 0.3071, bill: 0.3068, paid: 0.3062 },
    reference: 'BW-0418',
    freight: 365,
    clearing: 92.5,
  },
  {
    order: -8,
    arrived: -6,
    goods: [
      ['panel', 480, 10.2],
      ['downlight', 900, 3.1],
      ['flood', 38, 22.5],
    ],
    rates: { order: 0.3074, bill: 0.3075, paid: 0.3069 },
    reference: 'BW-0533',
    freight: 340,
    clearing: 88,
  },
];

function imports(books: DemoBooks, tl: Timeline) {
  const cal = books.calendar;
  SHIPMENTS.forEach((s, n) => {
    let order: InvoiceDocument;
    let bill: InvoiceDocument;
    let charges: InvoiceDocument;
    const ordered = cal.workdayOf(s.order, 9);
    tl.at(ordered, `import order ${n + 1}`, async () => {
      order = await books.document(
        'purchase_order',
        books.vendors.brightway,
        ordered,
        s.goods.map(([key, quantity, price]) => books.purchase(key, quantity, price)),
        {
          exchangeRate: s.rates.order,
          notes: 'CFR Shuwaikh port. Ship within 45 days of the order.',
          deliveryPlace: 'Shuwaikh store, Shuwaikh Industrial',
        },
      );
    });
    const arrived = cal.workdayOf(s.arrived, 18);
    tl.at(arrived, `import bill ${n + 1}`, async () => {
      bill = await books.fromOrder(order, 'bill', arrived, undefined, {
        exchangeRate: s.rates.bill,
        vendorReference: `${s.reference}/${arrived.slice(2, 4)}`,
      });
    });
    // Customs (5% of the value in dinars), sea freight and clearing, added to the stock's cost.
    const cleared = cal.workdayOf(s.arrived, 21);
    tl.at(cleared, `customs and freight ${n + 1}`, async () => {
      const fresh = (await db.documents.get(bill.id))!;
      const duty = round(fresh.totals.total * s.rates.bill * 0.05, 3);
      charges = await books.document(
        'bill',
        books.vendors.clearing,
        cleared,
        [
          books.custom('Customs duty 5%', 'رسوم جمركية 5%', 1, duty, '5200'),
          books.custom(
            'Sea freight Shenzhen – Shuwaikh',
            'شحن بحري من شنتشن إلى الشويخ',
            1,
            s.freight,
            '5200',
          ),
          books.custom(
            'Clearing and port handling',
            'التخليص والمناولة في الميناء',
            1,
            s.clearing,
            '5200',
          ),
        ],
        { vendorReference: `GCF-${7720 + n * 311}` },
      );
      await saveLandedCost(books.id, {
        billId: charges.id,
        sourceLineIds: charges.items.map((i) => i.id),
        targetBillId: bill.id,
        targetLineIds: [],
        method: 'value',
        notes: both(
          'Customs, freight and clearing of the shipment, shared by value',
          'الجمارك والشحن والتخليص للشحنة، موزعة حسب القيمة',
        ),
      });
    });
    const paid = cal.workdayOf(s.arrived, 26);
    tl.at(paid, `import paid ${n + 1}`, async () => {
      await books.pay(bill, {
        date: paid,
        method: 'bank_transfer',
        exchangeRate: s.rates.paid,
        reference: `NBK SWIFT ${s.reference}`,
      });
    });
    const agent = cal.workdayOf(s.arrived + 1, 4);
    tl.at(agent, `clearing agent paid ${n + 1}`, async () => {
      await books.pay(charges, { date: agent, method: 'bank_transfer', reference: 'NBK TRF' });
    });
  });
}

/** Cameras, recorders and locks from Dubai, in dirhams. */
function security(books: DemoBooks, tl: Timeline) {
  const cal = books.calendar;
  const goods = (camera: number, nvr: number, lock: number) => [
    books.purchase('camera', camera, 210),
    books.purchase('nvr', nvr, 700),
    books.purchase('lock', lock, 470),
  ];
  // The first delivery was billed without an order.
  let first: InvoiceDocument;
  const billed = cal.workdayOf(-12, 14);
  tl.at(billed, 'Jebel Ali bill 1', async () => {
    first = await books.document('bill', books.vendors.jebelali, billed, goods(48, 2, 14), {
      exchangeRate: 0.0836,
      vendorReference: 'JASS-INV-30981',
    });
  });
  const paid1 = cal.workdayOf(-11, 10);
  tl.at(paid1, 'Jebel Ali paid 1', async () => {
    await books.pay(first, {
      date: paid1,
      method: 'bank_transfer',
      exchangeRate: 0.0834,
      reference: 'NBK SWIFT JASS 30981',
    });
  });

  let order: InvoiceDocument;
  let second: InvoiceDocument;
  const ordered = cal.workdayOf(-8, 3);
  tl.at(ordered, 'Jebel Ali order 2', async () => {
    order = await books.document(
      'purchase_order',
      books.vendors.jebelali,
      ordered,
      goods(38, 4, 2),
      {
        exchangeRate: 0.0835,
      },
    );
  });
  const arrived = cal.workdayOf(-7, 12);
  tl.at(arrived, 'Jebel Ali bill 2', async () => {
    second = await books.fromOrder(order, 'bill', arrived, undefined, {
      exchangeRate: 0.0835,
      vendorReference: 'JASS-INV-31544',
    });
  });
  const paid2 = cal.workdayOf(-6, 8);
  tl.at(paid2, 'Jebel Ali paid 2', async () => {
    await books.pay(second, {
      date: paid2,
      method: 'bank_transfer',
      exchangeRate: 0.0837,
      reference: 'NBK SWIFT JASS 31544',
    });
  });

  // The next order is on its way: issued, not billed yet.
  const next = cal.workday(cal.ago(25));
  tl.at(next, 'Jebel Ali order 3', async () => {
    await books.document('purchase_order', books.vendors.jebelali, next, goods(40, 6, 20), {
      exchangeRate: 0.0836,
      notes: 'التسليم بالشاحنة إلى مستودع الشويخ.\nDeliver by truck to the Shuwaikh store.',
    });
  });
}

/* -------------------------------------------------------------------------- */
/* Shuwaikh Cables: every other month, paid by post-dated cheques             */
/* -------------------------------------------------------------------------- */

function cables(books: DemoBooks, tl: Timeline) {
  const cal = books.calendar;
  const months = [-12, -10, -8, -6, -4, -2];
  months.forEach((m, n) => {
    const billed = cal.workdayOf(m, 15);
    let bill: InvoiceDocument;
    let cheque: Payment | undefined;
    tl.at(billed, `cables bill ${n + 1}`, async () => {
      bill = await books.document(
        'bill',
        books.vendors.cables,
        billed,
        [books.purchase('cable', 30), books.purchase('switches', 80)],
        { vendorReference: `SCE/${String(2210 + n * 64)}` },
      );
    });
    if (m === -8) {
      // Two damaged rolls went back: a vendor credit used against the bill.
      const back = cal.workdayOf(m, 22);
      tl.at(back, 'cables vendor credit', async () => {
        const credit = await books.document(
          'vendor_credit',
          books.vendors.cables,
          back,
          [books.purchase('cable', 2)],
          { vendorReference: 'SCE/CN/118' },
        );
        await books.applyCredit(credit, bill, back);
      });
    }
    const issued = cal.workdayOf(m, 28);
    const last = n === months.length - 1;
    const chequeDate = last ? cal.ahead(9) : addDaysISO(issued, 30);
    const number = `000${417 + n}`;
    tl.at(issued, `cables cheque ${n + 1}`, async () => {
      cheque = await books.pay(bill, {
        date: issued,
        method: 'cheque',
        reference: number,
        cheque: { number, bank: 'NBOK', date: chequeDate, drawer: VENDORS.cables.name },
      });
    });
    const presented = nextWorkday(chequeDate);
    tl.at(presented, `cables cheque ${n + 1} cleared`, async () => {
      if (cheque)
        await clearCheque(cheque.id, { date: presented, bankAccountId: books.money('nbk') });
    });
  });
}

/* -------------------------------------------------------------------------- */
/* Al Sahel Technical Services: installation crews for the tower              */
/* -------------------------------------------------------------------------- */

function subcontractor(books: DemoBooks, tl: Timeline) {
  const cal = books.calendar;
  const stages: [month: number, amount: number][] = [
    [-10, 2650],
    [-7, 3150],
    [-4, 2400],
    [-1, 1250],
  ];
  stages.forEach(([m, amount], n) => {
    const billed = cal.workdayOf(m, 26);
    let bill: InvoiceDocument;
    tl.at(billed, `subcontractor bill ${n + 1}`, async () => {
      bill = await books.document(
        'bill',
        books.vendors.sahel,
        billed,
        [
          books.custom(
            `Installation crew – Al Bawaba Tower, stage ${n + 1}`,
            `طاقم تركيب – برج البوابة، المرحلة ${n + 1}`,
            1,
            amount,
            '5100',
          ),
        ],
        { vendorReference: `AST-${String(310 + n * 27)}` },
      );
    });
    // The last stage is still owed, whatever day the demo is loaded: paying it
    // on the 27th left no open bill (and empty payables) until the month ended.
    if (n === stages.length - 1) return;
    const paid = cal.workdayOf(m + 1, 27);
    tl.at(paid, `subcontractor paid ${n + 1}`, async () => {
      await books.pay(bill, { date: paid, method: 'bank_transfer', reference: 'NBK TRF' });
    });
  });
}

/* -------------------------------------------------------------------------- */
/* Laptops for the office: a bill line that becomes a fixed asset             */
/* -------------------------------------------------------------------------- */

function computers(books: DemoBooks, tl: Timeline) {
  const cal = books.calendar;
  let bill: InvoiceDocument;
  const billed = cal.workdayOf(-6, 12);
  tl.at(billed, 'laptops bill', async () => {
    bill = await books.document(
      'bill',
      books.vendors.sharq,
      billed,
      [
        books.custom('Laptop 14", Core i7, 16 GB', 'حاسب محمول 14 بوصة', 3, 345, '1520', 'pcs'),
        books.custom('Laser printer', 'طابعة ليزر', 1, 89, '6140', 'pcs'),
      ],
      { vendorReference: 'SCS-INV-77120' },
    );
    const line = bill.items[0];
    await saveAsset(
      createAsset(books.id, {
        name: 'Laptops for the office (3)',
        nameAr: 'حواسب محمولة للمكتب (3)',
        description: both('Accounts, sales and projects', 'الحسابات والمبيعات والمشاريع'),
        assetAccountId: books.account('1520').id,
        accumulatedAccountId: books.account('1530').id,
        expenseAccountId: books.account('6900').id,
        purchaseDate: billed,
        depreciationStart: billed,
        cost: 1035,
        salvageValue: 0,
        usefulLifeMonths: 36,
        source: 'bill',
        billId: bill.id,
        billLineId: line.id,
        location: both('Shuwaikh office', 'مكتب الشويخ'),
        custodian: 'Maryam Yousef Al-Kandari',
      }),
    );
  });
  const paid = cal.workdayOf(-6, 20);
  tl.at(paid, 'laptops paid', async () => {
    await books.pay(bill, {
      date: paid,
      method: 'bank_transfer',
      from: 'kfh',
      reference: 'KFH TRF',
    });
  });

  // Display shelving for the showroom, paid straight from the bank.
  const bought: ISODate = cal.workdayOf(-9, 14);
  tl.at(bought, 'showroom shelving', async () => {
    await saveAsset(
      createAsset(books.id, {
        name: 'Showroom display shelving',
        nameAr: 'رفوف عرض المعرض',
        description: both(
          'Lighting display walls and shelving, Al-Rai showroom',
          'جدران عرض الإنارة والرفوف، معرض الري',
        ),
        assetAccountId: books.account('1500').id,
        accumulatedAccountId: books.account('1510').id,
        expenseAccountId: books.account('6900').id,
        purchaseDate: bought,
        depreciationStart: bought,
        cost: 1860,
        salvageValue: 0,
        usefulLifeMonths: 60,
        source: 'purchase',
        paidFromAccountId: books.money('nbk'),
        location: both('Al-Rai showroom', 'معرض الري'),
        custodian: 'Mohammed Abdelrahman Hassan',
      }),
    );
  });
}
