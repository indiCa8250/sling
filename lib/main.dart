import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final s = Store();
  await s.load();
  runApp(App(s));
}

class App extends StatefulWidget {
  const App(this.s, {super.key});
  final Store s;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  Timer? splashTimer;
  bool showSplash = true;

  @override
  void initState() {
    super.initState();
    splashTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted) setState(() => showSplash = false);
    });
  }

  @override
  void dispose() {
    splashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Sling',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff087f5b)),
      scaffoldBackgroundColor: const Color(0xfff8faf8),
    ),
    home: showSplash ? const OpeningFlash() : Home(widget.s),
  );
}

class OpeningFlash extends StatelessWidget {
  const OpeningFlash({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Color(0xff116065),
    body: SizedBox.expand(
      child: Image(
        image: AssetImage('assets/sling-flash.png'),
        fit: BoxFit.contain,
      ),
    ),
  );
}

enum Unit { grams, ounces, pounds }

enum PriceUnit { pounds, ounces, grams, points }

enum Loss { waste, discrepancy }

enum SaleKind { sale, trade, loan }

extension UnitName on Unit {
  String get label => switch (this) {
    Unit.grams => 'grams',
    Unit.ounces => 'ounces',
    Unit.pounds => 'pounds',
  };
}

extension PriceUnitName on PriceUnit {
  String get label => switch (this) {
    PriceUnit.pounds => 'pounds',
    PriceUnit.ounces => 'ounces',
    PriceUnit.grams => 'grams',
    PriceUnit.points => 'points',
  };

  double get grams => switch (this) {
    PriceUnit.pounds => 453.59237,
    PriceUnit.ounces => 28.349523125,
    PriceUnit.grams => 1,
    PriceUnit.points => .1,
  };
}

double toGrams(double n, Unit u) => switch (u) {
  Unit.grams => n,
  Unit.ounces => n * 28.349523125,
  Unit.pounds => n * 453.59237,
};
double? number(String s) {
  final n = double.tryParse(s.trim());
  return n == null || n <= 0 ? null : n;
}

int? cash(String s) {
  final n = double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), ''));
  return n == null || n < 0 ? null : (n * 100).round();
}

String g(double n) => '${n.toStringAsFixed(n < 10 ? 2 : 1)} g';
String dollars(int n) => '\$${(n / 100).toStringAsFixed(2)}';
int loanBalance(Sale loan) =>
    (loan.cents - loan.paidCents).clamp(0, loan.cents).toInt();
String unitPrice(int cents, double grams, PriceUnit unit) {
  final price = (cents / 100) / (grams / unit.grams);
  return '\$${price.toStringAsFixed(price < 1 ? 3 : 2)}';
}

String date(DateTime d) => '${d.month}/${d.day}/${d.year}';

class Sale {
  Sale(
    this.grams,
    this.cents,
    this.at, {
    this.kind = SaleKind.sale,
    this.note = '',
    this.person = '',
    this.paidCents = 0,
  });
  final double grams;
  final int cents;
  final DateTime at;
  final SaleKind kind;
  final String note;
  final String person;
  final int paidCents;
  Map<String, dynamic> json() => {
    'g': grams,
    'c': cents,
    'at': at.toIso8601String(),
    'kind': kind.name,
    'note': note,
    'person': person,
    'paid': paidCents,
  };
  factory Sale.from(Map<String, dynamic> j) => Sale(
    (j['g'] as num).toDouble(),
    j['c'] as int,
    DateTime.parse(j['at'] as String),
    kind: switch ((j['kind'] as String?) ?? 'sale') {
      'front' => SaleKind.loan,
      final kind => SaleKind.values.byName(kind),
    },
    note: (j['note'] as String?) ?? '',
    person: (j['person'] as String?) ?? '',
    paidCents: (j['paid'] as num?)?.toInt() ?? 0,
  );
}

class Adjustment {
  Adjustment(this.grams, this.type, this.at, this.note);
  final double grams;
  final Loss type;
  final DateTime at;
  final String note;
  Map<String, dynamic> json() => {
    'g': grams,
    'type': type.name,
    'at': at.toIso8601String(),
    'note': note,
  };
  factory Adjustment.from(Map<String, dynamic> j) => Adjustment(
    (j['g'] as num).toDouble(),
    Loss.values.byName(j['type'] as String),
    DateTime.parse(j['at'] as String),
    (j['note'] as String?) ?? '',
  );
}

class Batch {
  Batch(
    this.id,
    this.name,
    this.bought,
    this.cost,
    this.at, {
    this.note = '',
    List<Sale>? sales,
    List<Adjustment>? losses,
  }) : sales = sales ?? [],
       losses = losses ?? [];
  final String id;
  String name, note;
  double bought;
  int cost;
  DateTime at;
  final List<Sale> sales;
  final List<Adjustment> losses;
  Iterable<Sale> get cashSales => sales.where((x) => x.kind == SaleKind.sale);
  Iterable<Sale> get trades => sales.where((x) => x.kind == SaleKind.trade);
  Iterable<Sale> get loans => sales.where((x) => x.kind == SaleKind.loan);
  double get sold => cashSales.fold(0, (a, b) => a + b.grams);
  double get traded => trades.fold(0, (a, b) => a + b.grams);
  double get loaned => loans.fold(0, (a, b) => a + b.grams);
  int get loansOwed =>
      loans.fold(0, (a, b) => a + (b.cents - b.paidCents).clamp(0, b.cents));
  int get loanRepayments => loans.fold(0, (a, b) => a + b.paidCents);
  double get moved => sales.fold(0, (a, b) => a + b.grams);
  double get waste =>
      losses.where((x) => x.type == Loss.waste).fold(0, (a, b) => a + b.grams);
  double get difference => losses
      .where((x) => x.type == Loss.discrepancy)
      .fold(0, (a, b) => a + b.grams);
  double get left =>
      (bought - moved - waste - difference).clamp(0, double.infinity);
  // Loan money becomes revenue only as it is actually repaid.
  int get revenue => cashSales.fold(0, (a, b) => a + b.cents) + loanRepayments;
  int get needed => (cost - revenue).clamp(0, cost);
  int get profit => (revenue - cost).clamp(0, 1 << 62);
  Map<String, dynamic> json() => {
    'id': id,
    'name': name,
    'bought': bought,
    'cost': cost,
    'at': at.toIso8601String(),
    'note': note,
    'sales': sales.map((x) => x.json()).toList(),
    'losses': losses.map((x) => x.json()).toList(),
  };
  factory Batch.from(Map<String, dynamic> j) => Batch(
    j['id'] as String,
    j['name'] as String,
    (j['bought'] as num).toDouble(),
    j['cost'] as int,
    DateTime.parse(j['at'] as String),
    note: (j['note'] as String?) ?? '',
    sales: ((j['sales'] as List?) ?? [])
        .map((x) => Sale.from(x as Map<String, dynamic>))
        .toList(),
    losses: ((j['losses'] as List?) ?? [])
        .map((x) => Adjustment.from(x as Map<String, dynamic>))
        .toList(),
  );
}

class Store extends ChangeNotifier {
  final batches = <Batch>[];
  static const key = 'sling_batches_v1';
  Future<void> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw != null) {
      batches.addAll(
        (jsonDecode(raw) as List).map(
          (x) => Batch.from(x as Map<String, dynamic>),
        ),
      );
    }
  }

  Future<void> save() async {
    await (await SharedPreferences.getInstance()).setString(
      key,
      jsonEncode(batches.map((x) => x.json()).toList()),
    );
    notifyListeners();
  }

  void add(Batch b) {
    batches.insert(0, b);
    save();
  }

  void remove(Batch b) {
    batches.remove(b);
    save();
  }

  void changed() => save();
}

class Home extends StatefulWidget {
  const Home(this.s, {super.key});
  final Store s;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  String? overviewBatchId;
  bool showingCompletedOnly = false;
  @override
  void initState() {
    super.initState();
    widget.s.addListener(redraw);
  }

  @override
  void dispose() {
    widget.s.removeListener(redraw);
    super.dispose();
  }

  void redraw() {
    if (mounted) setState(() {});
  }

  List<Batch> get b => widget.s.batches;

  bool isCompleted(Batch batch) =>
      batch.left <= 0.000001 && batch.cashSales.isNotEmpty;

  List<Batch> get activeBatches => b.where((x) => !isCompleted(x)).toList();

  List<Batch> get completedBatches => b.where(isCompleted).toList();

  IconData activityIcon(SaleKind kind) => switch (kind) {
    SaleKind.sale => Icons.sell_outlined,
    SaleKind.trade => Icons.swap_horiz,
    SaleKind.loan => Icons.handshake_outlined,
  };

  String activityTitle(Sale x) => switch (x.kind) {
    SaleKind.sale =>
      x.grams == 0 ? 'Sold (weight not entered)' : 'Sold ${g(x.grams)}',
    SaleKind.trade => 'Trade ${g(x.grams)}',
    SaleKind.loan =>
      x.grams == 0 ? 'Advance ${dollars(x.cents)}' : 'Loaned ${g(x.grams)}',
  };

  String activitySubtitle(Sale x) {
    final detail = x.kind == SaleKind.sale ? '' : x.note;
    return detail.isEmpty ? date(x.at) : '$detail • ${date(x.at)}';
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: const Text('SLING'),
      actions: [
        PopupMenuButton<_OverviewAction>(
          tooltip: 'Overview options',
          onSelected: overviewAction,
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: _OverviewAction.newPurchase,
              child: ListTile(
                leading: Icon(Icons.add_circle_outline),
                title: Text('Record a purchase'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            if (overviewBatchId != null && b.isNotEmpty) ...[
              const PopupMenuItem(
                value: _OverviewAction.edit,
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit batch'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: _OverviewAction.delete,
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.red),
                  title: Text('Delete batch'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            const PopupMenuItem(
              value: _OverviewAction.help,
              child: ListTile(
                leading: Icon(Icons.help_outline),
                title: Text('How it works'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
          icon: const Icon(Icons.more_vert),
        ),
      ],
    ),
    body: dashboard(),
  );
  Widget dashboard() {
    final selected = b.where((x) => x.id == overviewBatchId).firstOrNull;
    final shown = showingCompletedOnly
        ? completedBatches
        : selected == null
        ? activeBatches
        : [selected];
    final readOnly =
        showingCompletedOnly || (selected != null && isCompleted(selected));
    final sold = shown.fold(0.0, (a, x) => a + x.sold),
        loaned = shown.fold(0.0, (a, x) => a + x.loaned),
        left = shown.fold(0.0, (a, x) => a + x.left),
        waste = shown.fold(0.0, (a, x) => a + x.waste),
        diff = shown.fold(0.0, (a, x) => a + x.difference);
    final loansOwed = shown.fold(0, (a, x) => a + x.loansOwed);
    final owedByPerson = <String, int>{};
    for (final batch in shown) {
      for (final loan in batch.loans) {
        final balance = loanBalance(loan);
        if (balance > 0) {
          final person = loan.note.trim().isEmpty
              ? 'Person not named'
              : loan.note.trim();
          owedByPerson[person] = (owedByPerson[person] ?? 0) + balance;
        }
      }
    }
    final peopleOwed = owedByPerson.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Today at a glance',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          shown.isEmpty
              ? 'Add a purchase to start tracking your business.'
              : showingCompletedOnly
              ? 'All completed purchases combined.'
              : selected == null
              ? 'All ${activeBatches.length} active ${activeBatches.length == 1 ? 'purchase' : 'purchases'} combined.'
              : 'Showing ${selected.name}.',
        ),
        if (activeBatches.isNotEmpty || completedBatches.isNotEmpty) ...[
          const SizedBox(height: 14),
          heading('Showing'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ...activeBatches.expand(
                  (x) => [
                    ChoiceChip(
                      label: Text(x.name),
                      selected:
                          !showingCompletedOnly && overviewBatchId == x.id,
                      onSelected: (_) => setState(() {
                        showingCompletedOnly = false;
                        overviewBatchId = x.id;
                      }),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                if (completedBatches.isNotEmpty)
                  PopupMenuButton<String>(
                    tooltip: 'Completed purchases',
                    icon: const Icon(Icons.arrow_drop_down_circle_outlined),
                    onSelected: (value) => setState(() {
                      if (value == '__all_completed__') {
                        showingCompletedOnly = true;
                        overviewBatchId = null;
                      } else {
                        showingCompletedOnly = false;
                        overviewBatchId = value;
                      }
                    }),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: '__all_completed__',
                        child: ListTile(
                          leading: Icon(Icons.all_inclusive),
                          title: Text('All batches'),
                          subtitle: Text('Completed purchases combined'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      ...completedBatches.map(
                        (x) => PopupMenuItem(
                          value: x.id,
                          child: ListTile(
                            leading: const Icon(Icons.history),
                            title: Text(x.name),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        heading('Money and weight'),
        grid([
          pairedStat(
            'Sold',
            dollars(
              shown.fold(
                0,
                (a, x) => a + x.cashSales.fold(0, (m, sale) => m + sale.cents),
              ),
            ),
            g(sold),
            Icons.sell_outlined,
            onTap: readOnly
                ? null
                : activeBatches.isEmpty
                ? newBatch
                : recordSaleFromOverview,
          ),
          stat(
            'Left to sell',
            g(left),
            Icons.inventory_2_outlined,
            color: Colors.green,
          ),
          pairedStat(
            'Advances',
            dollars(loansOwed),
            g(loaned),
            Icons.handshake_outlined,
            onTap: readOnly
                ? null
                : activeBatches.isEmpty
                ? newBatch
                : chooseAdvanceAction,
          ),
          stat(
            'Waste',
            g(waste),
            Icons.delete_outline,
            color: waste > 0 ? Colors.red : null,
            onTap: readOnly
                ? null
                : activeBatches.isEmpty
                ? newBatch
                : () => recordLossFromOverview(Loss.waste),
          ),
          stat(
            'Weighing difference',
            g(diff),
            Icons.balance_outlined,
            color: diff > 0 ? Colors.orange : null,
            info: 'Weight missing when you check what is actually left on the scale.',
            onTap: readOnly
                ? null
                : activeBatches.isEmpty
                ? newBatch
                : () => recordLossFromOverview(Loss.discrepancy),
          ),
        ]),
        if (peopleOwed.isNotEmpty) ...[
          const SizedBox(height: 18),
          heading('Who owes you'),
          Card(
            child: Column(
              children: [
                for (final entry in peopleOwed.take(5))
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_outline),
                    title: Text(entry.key),
                    trailing: Text(
                      dollars(entry.value),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onTap: b.isEmpty ? null : recordRepaymentFromOverview,
                  ),
                if (peopleOwed.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('+ ${peopleOwed.length - 5} more'),
                  ),
              ],
            ),
          ),
        ],
        if (selected != null) ...[
          const SizedBox(height: 18),
          selectedBatchDetails(selected),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: newBatch,
          icon: const Icon(Icons.add),
          label: const Text('Record a purchase'),
        ),
      ],
    );
  }

  Widget selectedBatchDetails(Batch batch) {
    Widget line(String label, String value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(fontWeight: bold ? FontWeight.bold : null),
          ),
        ],
      ),
    );

    final activities = [
      ...batch.sales.map(
        (x) => (
          at: x.at,
          icon: activityIcon(x.kind),
          title: activityTitle(x),
          subtitle: activitySubtitle(x),
          amount: x.kind == SaleKind.loan
              ? loanBalance(x) == 0
                    ? 'Paid back'
                    : '${dollars(loanBalance(x))} owed'
              : x.kind == SaleKind.sale
              ? dollars(x.cents)
              : 'Trade',
        ),
      ),
      ...batch.losses.map(
        (x) => (
          at: x.at,
          icon: x.type == Loss.waste
              ? Icons.delete_outline
              : Icons.balance_outlined,
          title: x.type == Loss.waste
              ? 'Waste: ${g(x.grams)}'
              : 'Weighing difference: ${g(x.grams)}',
          subtitle: x.note.isEmpty ? date(x.at) : '${x.note} • ${date(x.at)}',
          amount: '',
        ),
      ),
    ]..sort((a, b) => b.at.compareTo(a.at));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading('${batch.name} stats'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                line('Purchased', g(batch.bought)),
                line('Sold', g(batch.sold)),
                line('Traded', g(batch.traded)),
                line('Loaned', g(batch.loaned)),
                line('Waste', g(batch.waste)),
                line('Weighing difference', g(batch.difference)),
                const Divider(),
                line('Left to sell', g(batch.left), bold: true),
                line('Paid', dollars(batch.cost)),
                line('Sales made', dollars(batch.revenue)),
                line('Loans owed', dollars(batch.loansOwed)),
                line('Loan repayments', dollars(batch.loanRepayments)),
                line('Needed to break even', dollars(batch.needed), bold: true),
                if (batch.profit > 0)
                  line('Profit', dollars(batch.profit), bold: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        heading('Activity'),
        if (activities.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No activity recorded yet.'),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (final item in activities)
                  ListTile(
                    leading: Icon(item.icon),
                    title: Text(item.title),
                    subtitle: Text(item.subtitle),
                    trailing: item.amount.isEmpty
                        ? null
                        : Text(
                            item.amount,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> overviewAction(_OverviewAction action) async {
    if (action == _OverviewAction.newPurchase) {
      await newBatch();
      return;
    }
    if (action == _OverviewAction.help) {
      await showHelp();
      return;
    }
    final selected = b.where((x) => x.id == overviewBatchId).firstOrNull;
    if (showingCompletedOnly || (selected != null && isCompleted(selected))) {
      return;
    }
    if (activeBatches.isEmpty) {
      await newBatch();
      return;
    }
    switch (action) {
      case _OverviewAction.sale:
        await recordSaleFromOverview();
        return;
      case _OverviewAction.editSale:
        await editOverviewSale();
        return;
      case _OverviewAction.deleteSale:
        await deleteOverviewSale();
        return;
      case _OverviewAction.waste:
        await recordLossFromOverview(Loss.waste);
        return;
      case _OverviewAction.editWaste:
        await editOverviewLoss(Loss.waste);
        return;
      case _OverviewAction.deleteWaste:
        await deleteOverviewLoss(Loss.waste);
        return;
      case _OverviewAction.checkWeight:
        await recordLossFromOverview(Loss.discrepancy);
        return;
      case _OverviewAction.editWeight:
        await editOverviewLoss(Loss.discrepancy);
        return;
      case _OverviewAction.deleteWeight:
        await deleteOverviewLoss(Loss.discrepancy);
        return;
      case _OverviewAction.advance:
        await recordActivityFromOverview(SaleKind.loan);
        return;
      case _OverviewAction.editAdvance:
        await editOverviewAdvance();
        return;
      case _OverviewAction.deleteAdvance:
        await deleteOverviewAdvance();
        return;
      case _OverviewAction.repayment:
        await recordRepaymentFromOverview();
        return;
      case _OverviewAction.editRepayment:
        await editOverviewRepayment();
        return;
      case _OverviewAction.newPurchase:
      case _OverviewAction.edit:
      case _OverviewAction.delete:
        break;
      case _OverviewAction.help:
        break;
    }
    final batch = await selectedOverviewBatch();
    if (batch == null || !mounted) return;
    if (action == _OverviewAction.edit) {
      await editBatch(batch);
    } else {
      await deleteBatch(batch);
      if (overviewBatchId == batch.id && !b.contains(batch)) {
        setState(() => overviewBatchId = null);
      }
    }
  }

  Future<void> showHelp() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('How Sling works'),
        content: SizedBox(width: 420, child: help()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<Batch?> selectedOverviewBatch() {
    final selected = b.where((x) => x.id == overviewBatchId).firstOrNull;
    if (selected != null || activeBatches.length == 1) {
      return Future.value(selected ?? activeBatches.first);
    }
    return showDialog<Batch>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose a batch'),
        children: activeBatches
            .map(
              (batch) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, batch),
                child: Text(batch.name),
              ),
            )
            .toList(),
      ),
    );
  }

  Future<void> recordSaleFromOverview() async {
    final batch = await selectedOverviewBatch();
    if (batch == null || !mounted) return;
    await quickEntry(batch);
  }

  Future<void> recordLossFromOverview(Loss type) async {
    final batch = await selectedOverviewBatch();
    if (batch == null || !mounted) return;
    await quickEntry(batch, lossType: type);
  }

  Future<void> recordActivityFromOverview(SaleKind kind) async {
    final batch = await selectedOverviewBatch();
    if (batch == null || !mounted) return;
    await quickEntry(batch, activityKind: kind);
  }

  Future<void> chooseAdvanceAction() async {
    final action = await showDialog<_AdvanceAction>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Advances'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _AdvanceAction.newAdvance),
            child: const ListTile(
              leading: Icon(Icons.handshake_outlined),
              title: Text('Enter new advance'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _AdvanceAction.repay),
            child: const ListTile(
              leading: Icon(Icons.paid_outlined),
              title: Text('Pay off an advance'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == _AdvanceAction.newAdvance) {
      await recordActivityFromOverview(SaleKind.loan);
    } else {
      await recordRepaymentFromOverview();
    }
  }

  Future<void> recordRepaymentFromOverview() async {
    final batch = await selectedOverviewBatch();
    if (batch == null || !mounted) return;
    final loans = batch.loans.where((x) => loanBalance(x) > 0).toList();
    if (loans.isEmpty) return;
    Sale selectedLoan = loans.first;
    final amount = TextEditingController(
      text: (loanBalance(selectedLoan) / 100).toStringAsFixed(2),
    );
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Record loan repayment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButton<Sale>(
                value: selectedLoan,
                isExpanded: true,
                items: loans
                    .map(
                      (loan) => DropdownMenuItem(
                        value: loan,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              loan.note.isEmpty
                                  ? 'Loan from ${date(loan.at)}'
                                  : loan.note,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${dollars(loanBalance(loan))} owed • ${loan.grams == 0 ? 'money only' : g(loan.grams)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (loan) {
                  if (loan != null) {
                    set(() {
                      selectedLoan = loan;
                      amount.text = (loanBalance(loan) / 100).toStringAsFixed(
                        2,
                      );
                    });
                  }
                },
              ),
              Text('Still owed: ${dollars(loanBalance(selectedLoan))}'),
              const SizedBox(height: 12),
              if (error != null) ...[
                Text(error!, style: TextStyle(color: Colors.red.shade700)),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount repaid',
                  prefixText: '\$',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                final payment = cash(amount.text);
                final owed = loanBalance(selectedLoan);
                if (payment == null || payment <= 0) {
                  set(() => error = 'Enter the amount repaid.');
                  return;
                }
                if (payment > owed) {
                  set(() => error = 'That is more than the amount still owed.');
                  return;
                }
                final index = batch.sales.indexOf(selectedLoan);
                if (index == -1) return;
                batch.sales[index] = Sale(
                  selectedLoan.grams,
                  selectedLoan.cents,
                  selectedLoan.at,
                  kind: SaleKind.loan,
                  note: selectedLoan.note,
                  person: selectedLoan.person,
                  paidCents: selectedLoan.paidCents + payment,
                );
                widget.s.changed();
                Navigator.pop(dialogContext);
              },
              child: const Text('Save repayment'),
            ),
          ],
        ),
      ),
    );
  }

  Future<Sale?> chooseOverviewSale(
    Batch batch,
    Iterable<Sale> choices,
  ) => showDialog<Sale>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Choose a record'),
      children: choices
          .map(
            (sale) => SimpleDialogOption(
              onPressed: () => Navigator.pop(context, sale),
              child: ListTile(
                leading: Icon(
                  sale.kind == SaleKind.loan
                      ? Icons.handshake_outlined
                      : Icons.sell_outlined,
                ),
                title: Text(
                  sale.kind == SaleKind.loan
                      ? (sale.note.isEmpty ? 'Advance' : sale.note)
                      : 'Sale',
                ),
                subtitle: Text(
                  sale.kind == SaleKind.loan
                      ? '${dollars(loanBalance(sale))} still owed • ${date(sale.at)}'
                      : '${dollars(sale.cents)} • ${date(sale.at)}',
                ),
              ),
            ),
          )
          .toList(),
    ),
  );

  Future<Adjustment?> chooseOverviewLoss(Batch batch, Loss type) =>
      showDialog<Adjustment>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(
            type == Loss.waste ? 'Choose waste' : 'Choose weight check',
          ),
          children: batch.losses
              .where((loss) => loss.type == type)
              .map(
                (loss) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, loss),
                  child: ListTile(
                    leading: Icon(
                      type == Loss.waste
                          ? Icons.delete_outline
                          : Icons.balance_outlined,
                    ),
                    title: Text(g(loss.grams)),
                    subtitle: Text(
                      loss.note.isEmpty
                          ? date(loss.at)
                          : '${loss.note} • ${date(loss.at)}',
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      );

  Future<void> editOverviewSale() async {
    final batch = await selectedOverviewBatch();
    if (batch == null || !mounted) return;
    final sale = await chooseOverviewSale(
      batch,
      batch.sales.where((sale) => sale.kind == SaleKind.sale),
    );
    if (sale == null || !mounted) return;
    final weight = TextEditingController(
      text: sale.grams == 0 ? '' : sale.grams.toStringAsFixed(4),
    );
    final amount = TextEditingController(
      text: (sale.cents / 100).toStringAsFixed(2),
    );
    Unit unit = Unit.grams;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Edit sale'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null)
                Text(error!, style: TextStyle(color: Colors.red.shade700)),
              TextField(
                controller: weight,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Weight (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount received',
                  prefixText: '\$',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                final grams = weight.text.trim().isEmpty
                    ? 0.0
                    : number(weight.text);
                final cents = cash(amount.text);
                if (grams == null || cents == null) {
                  set(() => error = 'Enter a valid price and weight.');
                  return;
                }
                final available = batch.left + sale.grams;
                if (toGrams(grams, unit) > available + .00001) {
                  set(
                    () => error = 'That is more than this batch has available.',
                  );
                  return;
                }
                final index = batch.sales.indexOf(sale);
                if (index == -1) return;
                batch.sales[index] = Sale(toGrams(grams, unit), cents, sale.at);
                widget.s.changed();
                Navigator.pop(dialogContext);
              },
              child: const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> editOverviewLoss(Loss type) async {
    final batch = await selectedOverviewBatch();
    if (batch == null || !mounted) return;
    final loss = await chooseOverviewLoss(batch, type);
    if (loss == null || !mounted) return;
    final weight = TextEditingController(text: loss.grams.toStringAsFixed(4));
    final note = TextEditingController(text: loss.note);
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(type == Loss.waste ? 'Edit waste' : 'Edit weight check'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null)
                Text(error!, style: TextStyle(color: Colors.red.shade700)),
              TextField(
                controller: weight,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Weight',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: note,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                final grams = number(weight.text);
                if (grams == null || grams <= 0) {
                  set(() => error = 'Enter a positive weight.');
                  return;
                }
                if (grams > batch.left + loss.grams + .00001) {
                  set(
                    () => error = 'That is more than this batch has available.',
                  );
                  return;
                }
                final index = batch.losses.indexOf(loss);
                if (index == -1) return;
                batch.losses[index] = Adjustment(
                  grams,
                  loss.type,
                  loss.at,
                  note.text.trim(),
                );
                widget.s.changed();
                Navigator.pop(dialogContext);
              },
              child: const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> editOverviewAdvance() async {
    final batch = await selectedOverviewBatch();
    if (batch == null || !mounted) return;
    final loan = await chooseOverviewSale(batch, batch.loans);
    if (loan == null || !mounted) return;
    final amount = TextEditingController(
      text: (loan.cents / 100).toStringAsFixed(2),
    );
    final note = TextEditingController(text: loan.note);
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Edit advance'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null)
                Text(error!, style: TextStyle(color: Colors.red.shade700)),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount owed',
                  prefixText: '\$',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: note,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Who it was loaned to',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                final cents = cash(amount.text);
                if (cents == null || cents <= 0) {
                  set(() => error = 'Enter the amount owed.');
                  return;
                }
                if (cents < loan.paidCents) {
                  set(
                    () => error =
                        'It cannot be less than repayments already recorded.',
                  );
                  return;
                }
                final index = batch.sales.indexOf(loan);
                if (index == -1) return;
                batch.sales[index] = Sale(
                  loan.grams,
                  cents,
                  loan.at,
                  kind: SaleKind.loan,
                  note: note.text.trim(),
                  person: loan.person,
                  paidCents: loan.paidCents,
                );
                widget.s.changed();
                Navigator.pop(dialogContext);
              },
              child: const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> editOverviewRepayment() async {
    final batch = await selectedOverviewBatch();
    if (batch == null || !mounted) return;
    final loans = batch.loans.where((loan) => loan.paidCents > 0).toList();
    final loan = await chooseOverviewSale(batch, loans);
    if (loan == null || !mounted) return;
    final amount = TextEditingController(
      text: (loan.paidCents / 100).toStringAsFixed(2),
    );
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Edit repayment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(loan.note.isEmpty ? 'Advance' : loan.note),
              if (error != null)
                Text(error!, style: TextStyle(color: Colors.red.shade700)),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Total repaid',
                  prefixText: '\$',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                final cents = cash(amount.text);
                if (cents == null || cents < 0 || cents > loan.cents) {
                  set(
                    () => error = 'Enter a total repaid up to the amount owed.',
                  );
                  return;
                }
                final index = batch.sales.indexOf(loan);
                if (index == -1) return;
                batch.sales[index] = Sale(
                  loan.grams,
                  loan.cents,
                  loan.at,
                  kind: SaleKind.loan,
                  note: loan.note,
                  person: loan.person,
                  paidCents: cents,
                );
                widget.s.changed();
                Navigator.pop(dialogContext);
              },
              child: const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> confirmOverviewDelete(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> deleteOverviewSale() async {
    final batch = await selectedOverviewBatch();
    if (batch == null || !mounted) return;
    final sale = await chooseOverviewSale(
      batch,
      batch.sales.where((sale) => sale.kind == SaleKind.sale),
    );
    if (sale == null || !mounted) return;
    if (!await confirmOverviewDelete(
      'Delete sale?',
      'This cannot be undone.',
    )) {
      return;
    }
    batch.sales.remove(sale);
    widget.s.changed();
  }

  Future<void> deleteOverviewAdvance() async {
    final batch = await selectedOverviewBatch();
    if (batch == null || !mounted) return;
    final loan = await chooseOverviewSale(batch, batch.loans);
    if (loan == null || !mounted) return;
    if (!await confirmOverviewDelete(
      'Delete advance?',
      'This cannot be undone.',
    )) {
      return;
    }
    batch.sales.remove(loan);
    widget.s.changed();
  }

  Future<void> deleteOverviewLoss(Loss type) async {
    final batch = await selectedOverviewBatch();
    if (batch == null || !mounted) return;
    final loss = await chooseOverviewLoss(batch, type);
    if (loss == null || !mounted) return;
    if (!await confirmOverviewDelete(
      type == Loss.waste ? 'Delete waste?' : 'Delete weight check?',
      'This cannot be undone.',
    )) {
      return;
    }
    batch.losses.remove(loss);
    widget.s.changed();
  }

  Future<void> quickEntry(
    Batch batch, {
    Loss? lossType,
    SaleKind? activityKind,
  }) async {
    final weightController = TextEditingController();
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    Unit unit = Unit.grams;
    String? error;
    final isSale = lossType == null && activityKind == null;
    final isLoss = lossType != null;
    final isTrade = activityKind == SaleKind.trade;
    final isLoan = activityKind == SaleKind.loan;
    final title = isSale
        ? 'Record a sale'
        : isLoss
        ? lossType == Loss.waste
              ? 'Record waste'
              : 'Check remaining weight'
        : isTrade
        ? 'Record a trade'
        : 'Record a loan / advance';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, set) {
          Widget input(
            TextEditingController controller,
            String label, {
            String? prefix,
            TextInputType? keyboardType,
            int maxLines = 1,
          }) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              maxLines: maxLines,
              decoration: InputDecoration(
                labelText: label,
                prefixText: prefix,
                border: const OutlineInputBorder(),
              ),
            ),
          );
          Widget weightInput() => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: input(
                    weightController,
                    isLoss && lossType == Loss.discrepancy
                        ? 'Actual weight left'
                        : isSale || isLoan
                        ? 'Weight (optional)'
                        : 'Weight',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<Unit>(
                  value: unit,
                  items: Unit.values
                      .map(
                        (x) => DropdownMenuItem(value: x, child: Text(x.label)),
                      )
                      .toList(),
                  onChanged: (x) {
                    if (x != null) set(() => unit = x);
                  },
                ),
              ],
            ),
          );
          return AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (error != null) ...[
                    Text(error!, style: TextStyle(color: Colors.red.shade700)),
                    const SizedBox(height: 10),
                  ],
                  weightInput(),
                  if (isSale)
                    input(
                      amountController,
                      'Amount received',
                      prefix: '\$',
                      keyboardType: TextInputType.number,
                    ),
                  if (isTrade) input(noteController, 'Traded for', maxLines: 2),
                  if (isLoan) ...[
                    input(
                      amountController,
                      'Amount owed',
                      prefix: '\$',
                      keyboardType: TextInputType.number,
                    ),
                    input(
                      noteController,
                      'Note (who it was loaned to)',
                      maxLines: 2,
                    ),
                  ],
                  if (isLoss)
                    input(noteController, 'Note (optional)', maxLines: 2),
                  if (isLoss && lossType == Loss.discrepancy)
                    const Text(
                      'Enter 0 if you are out of product.',
                      style: TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
              FilledButton(
                onPressed: () {
                  final n =
                      (isSale || isLoan) && weightController.text.trim().isEmpty
                      ? 0.0
                      : number(weightController.text);
                  if (n == null) {
                    set(
                      () => error = lossType == Loss.discrepancy
                          ? 'Enter the remaining weight, or 0 if you are out.'
                          : 'Enter the weight.',
                    );
                    return;
                  }
                  final grams = toGrams(n, unit);
                  if (grams > batch.left + .00001) {
                    set(() => error = 'That is more than this batch has left.');
                    return;
                  }
                  if (isSale) {
                    final cents = cash(amountController.text);
                    if (cents == null) {
                      set(() => error = 'Enter the sale price.');
                      return;
                    }
                    batch.sales.insert(0, Sale(grams, cents, DateTime.now()));
                  } else if (isLoss) {
                    if (lossType == Loss.waste) {
                      if (grams <= 0) {
                        set(() => error = 'Enter the waste weight.');
                        return;
                      }
                      batch.losses.insert(
                        0,
                        Adjustment(
                          grams,
                          Loss.waste,
                          DateTime.now(),
                          noteController.text.trim(),
                        ),
                      );
                    } else {
                      final missing = batch.left - grams;
                      if (missing < .00001) {
                        set(
                          () =>
                              error = 'Your scale matches the expected weight.',
                        );
                        return;
                      }
                      batch.losses.insert(
                        0,
                        Adjustment(
                          missing,
                          Loss.discrepancy,
                          DateTime.now(),
                          noteController.text.trim(),
                        ),
                      );
                    }
                  } else {
                    if (grams <= 0 && !isLoan) {
                      set(() => error = 'Enter the weight.');
                      return;
                    }
                    final cents = isLoan ? cash(amountController.text) : 0;
                    if (isLoan && (cents == null || cents <= 0)) {
                      set(() => error = 'Enter the amount owed.');
                      return;
                    }
                    if (isTrade && noteController.text.trim().isEmpty) {
                      set(() => error = 'Enter what you traded for.');
                      return;
                    }
                    batch.sales.insert(
                      0,
                      Sale(
                        grams,
                        cents ?? 0,
                        DateTime.now(),
                        kind: activityKind!,
                        note: noteController.text.trim(),
                      ),
                    );
                  }
                  widget.s.changed();
                  Navigator.pop(dialogContext);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget heading(String s) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(s, style: Theme.of(context).textTheme.titleMedium),
  );
  Widget grid(List<Widget> x) => Wrap(spacing: 10, runSpacing: 10, children: x);
  Widget stat(
    String l,
    String v,
    IconData i, {
    Color? color,
    String? info,
    VoidCallback? onTap,
  }) => SizedBox(
    width: ((MediaQuery.sizeOf(context).width - 42) / 2)
        .clamp(0, 300)
        .toDouble(),
    child: Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(i, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            l,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        if (info != null) ...[
                          const SizedBox(width: 3),
                          Tooltip(
                            message: info,
                            child: Icon(
                              Icons.info_outline,
                              size: 15,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget pairedStat(
    String label,
    String money,
    String weight,
    IconData icon, {
    VoidCallback? onTap,
  }) => SizedBox(
    width: ((MediaQuery.sizeOf(context).width - 42) / 2)
        .clamp(0, 300)
        .toDouble(),
    child: Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      money,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(weight, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 3),
                    Text(label, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget batches() => b.isEmpty
      ? Center(child: const Text('Use Overview to record your first purchase.'))
      : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Separate batches',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 5),
            const Text(
              'Each label keeps its own sales, waste, and break-even amount.',
            ),
            const SizedBox(height: 15),
            ...b.map(
              (x) => Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => BatchView(widget.s, x)),
                  ),
                  title: Text(
                    x.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${g(x.left)} left  •  ${dollars(x.needed)} to break even',
                  ),
                  trailing: PopupMenuButton<_BatchListAction>(
                    tooltip: 'Batch options',
                    onSelected: (action) {
                      switch (action) {
                        case _BatchListAction.edit:
                          editBatch(x);
                        case _BatchListAction.delete:
                          deleteBatch(x);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _BatchListAction.edit,
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Edit purchase'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: _BatchListAction.delete,
                        child: ListTile(
                          leading: Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                          title: Text('Delete batch'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );

  Future<void> deleteBatch(Batch batch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this batch?'),
        content: Text(
          'This removes ${batch.name}, including its sales and loss records. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete batch'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.s.remove(batch);
  }

  Widget help() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'How Sling works',
        style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
      ),
      SizedBox(height: 18),
      Help(
        'Keep every purchase separate',
        'Each new purchase gets an editable label and its own sales and statistics.',
      ),
      Help(
        'Use any weight unit',
        'Enter grams, ounces, or pounds. Sling converts them internally to grams for accurate inventory.',
      ),
      Help(
        'Waste vs. weighing difference',
        'Waste is product you cannot sell. Weighing difference is a shortage from over/under weighing or recounting. Both reduce stock but remain separate.',
      ),
      Help(
        'Break-even and profit',
        'Sales first repay a batch cost. Any amount above it is profit. Overview combines every batch.',
      ),
      const SizedBox(height: 8),
      const Divider(),
      const SizedBox(height: 16),
      Text('About', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SLING',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text('Version 1.0.0'),
              SizedBox(height: 16),
              Text('Created by indica aka Fc'),
              SizedBox(height: 4),
              SelectableText('indica8250@proton.me'),
            ],
          ),
        ),
      ),
    ],
  );
  Future<void> newBatch() async {
    final name = TextEditingController(),
        weight = TextEditingController(),
        cost = TextEditingController(),
        note = TextEditingController();
    Unit unit = Unit.grams;
    await sheet('Record a purchase', [
      field(
        name,
        'Product / batch label',
        hint: 'Example: Blue batch - Sept 28',
      ),
      weightField(weight, unit, (x) => unit = x),
      field(
        cost,
        'Total amount paid',
        prefix: '\$',
        keyboard: TextInputType.number,
      ),
      field(note, 'Note (optional)', max: 2),
      FilledButton(
        onPressed: () {
          final w = number(weight.text), p = cash(cost.text);
          if (name.text.trim().isEmpty || w == null || p == null) {
            err('Enter a label, weight, and price.');
            return;
          }
          widget.s.add(
            Batch(
              DateTime.now().microsecondsSinceEpoch.toString(),
              name.text.trim(),
              toGrams(w, unit),
              p,
              DateTime.now(),
              note: note.text.trim(),
            ),
          );
          Navigator.pop(context);
        },
        child: const Text('Save purchase'),
      ),
    ]);
  }

  Future<void> editBatch(Batch batch) async {
    final name = TextEditingController(text: batch.name);
    final purchaseWeight = TextEditingController(
      text: batch.bought.toStringAsFixed(4),
    );
    final cost = TextEditingController(
      text: (batch.cost / 100).toStringAsFixed(2),
    );
    final note = TextEditingController(text: batch.note);
    Unit unit = Unit.grams;
    await sheet('Edit purchase', [
      field(name, 'Product / batch label'),
      weightField(purchaseWeight, unit, (x) => unit = x),
      field(
        cost,
        'Total amount paid',
        prefix: '\$',
        keyboard: TextInputType.number,
      ),
      field(note, 'Note (optional)', max: 2),
      FilledButton(
        onPressed: () {
          final enteredWeight = number(purchaseWeight.text);
          final enteredCost = cash(cost.text);
          if (name.text.trim().isEmpty ||
              enteredWeight == null ||
              enteredCost == null) {
            err('Enter a label, weight, and price.');
            return;
          }
          final grams = toGrams(enteredWeight, unit);
          final alreadyAccountedFor =
              batch.sold + batch.waste + batch.difference;
          if (grams + .00001 < alreadyAccountedFor) {
            err(
              'The purchase weight cannot be less than what is already sold or lost.',
            );
            return;
          }
          batch.name = name.text.trim();
          batch.bought = grams;
          batch.cost = enteredCost;
          batch.note = note.text.trim();
          widget.s.changed();
          Navigator.pop(context);
        },
        child: const Text('Save changes'),
      ),
    ]);
  }

  Future<void> sheet(String title, List<Widget> children) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (c) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(c).bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(c).textTheme.headlineSmall),
                const SizedBox(height: 18),
                ...children,
              ],
            ),
          ),
        ),
      );
  Widget field(
    TextEditingController c,
    String label, {
    String? hint,
    String? prefix,
    TextInputType? keyboard,
    int max = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: c,
      keyboardType: keyboard,
      maxLines: max,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefix,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  Widget weightField(
    TextEditingController c,
    Unit unit,
    ValueChanged<Unit> change,
  ) => StatefulBuilder(
    builder: (context, set) => Row(
      children: [
        Expanded(
          child: field(
            c,
            'Weight',
            hint: 'Example: 1.24',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
        ),
        const SizedBox(width: 10),
        DropdownButton(
          value: unit,
          items: Unit.values
              .map((x) => DropdownMenuItem(value: x, child: Text(x.label)))
              .toList(),
          onChanged: (x) {
            if (x != null) {
              set(() => unit = x);
              change(x);
            }
          },
        ),
      ],
    ),
  );
  void err(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
}

class BatchView extends StatefulWidget {
  const BatchView(
    this.store,
    this.batch, {
    super.key,
    this.openSale = false,
    this.openLoss,
    this.openActivity,
  });
  final Store store;
  final Batch batch;
  final bool openSale;
  final Loss? openLoss;
  final SaleKind? openActivity;
  @override
  State<BatchView> createState() => _BatchViewState();
}

class _BatchViewState extends State<BatchView> {
  PriceUnit priceUnit = PriceUnit.grams;
  @override
  void initState() {
    super.initState();
    widget.store.addListener(redraw);
    if (widget.openSale) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) sale();
      });
    } else if (widget.openLoss != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) loss(initialType: widget.openLoss!);
      });
    } else if (widget.openActivity != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) activity(initialType: widget.openActivity!);
      });
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(redraw);
    super.dispose();
  }

  void redraw() {
    if (mounted) setState(() {});
  }

  Batch get b => widget.batch;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: Text(b.name),
      actions: [
        PopupMenuButton<_BatchAction>(
          onSelected: (action) {
            switch (action) {
              case _BatchAction.edit:
                editBatch();
              case _BatchAction.delete:
                deleteBatch();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _BatchAction.edit,
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('Edit purchase details'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: _BatchAction.delete,
              child: ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.red),
                title: Text('Delete this batch'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Batch stats', style: Theme.of(c).textTheme.headlineSmall),
        if (b.note.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(b.note, style: Theme.of(c).textTheme.bodyMedium),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                line('Purchased', g(b.bought)),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Unit price: ${unitPrice(b.cost, b.bought, priceUnit)} / ',
                        style: Theme.of(c).textTheme.bodySmall,
                      ),
                      DropdownButton<PriceUnit>(
                        value: priceUnit,
                        isDense: true,
                        underline: const SizedBox(),
                        items: PriceUnit.values
                            .map(
                              (x) => DropdownMenuItem(
                                value: x,
                                child: Text(x.label),
                              ),
                            )
                            .toList(),
                        onChanged: (x) {
                          if (x != null) setState(() => priceUnit = x);
                        },
                      ),
                    ],
                  ),
                ),
                line('Sold', g(b.sold)),
                line('Traded', g(b.traded)),
                line('Loaned', g(b.loaned)),
                line('Waste', g(b.waste)),
                line('Weighing difference', g(b.difference)),
                const Divider(),
                line('Left to sell', g(b.left), true),
                const SizedBox(height: 8),
                line('Paid', dollars(b.cost)),
                line('Sales made', dollars(b.revenue)),
                line('Loans owed', dollars(b.loansOwed)),
                line('Loan repayments', dollars(b.loanRepayments)),
                line('Needed to break even', dollars(b.needed), true),
                if (b.profit > 0)
                  line('Profit', dollars(b.profit), true, Colors.green),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: sale,
                icon: const Icon(Icons.sell),
                label: const Text('Record sale'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: loss,
                icon: const Icon(Icons.tune),
                label: const Text('Record waste / check weight'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => activity(),
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Record trade or loan'),
        ),
        const SizedBox(height: 20),
        Text('Activity', style: Theme.of(c).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (b.sales.isEmpty && b.losses.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No activity recorded yet.'),
            ),
          ),
        ...b.sales.map(
          (x) => Card(
            child: ListTile(
              leading: Icon(activityIcon(x.kind)),
              title: Text(activityTitle(x)),
              subtitle: Text(activitySubtitle(x)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    x.kind == SaleKind.loan
                        ? loanBalance(x) == 0
                              ? 'Paid back'
                              : '${dollars(loanBalance(x))} owed'
                        : x.kind == SaleKind.sale
                        ? dollars(x.cents)
                        : 'Trade',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  PopupMenuButton<_SaleAction>(
                    tooltip: 'Activity options',
                    onSelected: (action) {
                      switch (action) {
                        case _SaleAction.edit:
                          editSale(x);
                        case _SaleAction.repay:
                          repayLoan(x);
                        case _SaleAction.delete:
                          deleteSale(x);
                      }
                    },
                    itemBuilder: (context) => [
                      if (x.kind == SaleKind.loan && loanBalance(x) > 0)
                        const PopupMenuItem(
                          value: _SaleAction.repay,
                          child: ListTile(
                            leading: Icon(Icons.paid_outlined),
                            title: Text('Record repayment'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      const PopupMenuItem(
                        value: _SaleAction.edit,
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Edit activity'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: _SaleAction.delete,
                        child: ListTile(
                          leading: Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                          title: Text('Delete activity'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        ...b.losses.map(
          (x) => Card(
            child: ListTile(
              leading: Icon(
                x.type == Loss.waste
                    ? Icons.delete_outline
                    : Icons.balance_outlined,
              ),
              title: Text(
                '${x.type == Loss.waste ? 'Waste' : 'Weighing difference'}: ${g(x.grams)}',
              ),
              subtitle: Text(
                x.note.isEmpty ? date(x.at) : '${x.note} • ${date(x.at)}',
              ),
              trailing: PopupMenuButton<_LossAction>(
                tooltip: 'Loss options',
                onSelected: (action) {
                  switch (action) {
                    case _LossAction.edit:
                      editLoss(x);
                    case _LossAction.delete:
                      deleteLoss(x);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _LossAction.edit,
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit record'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: _LossAction.delete,
                    child: ListTile(
                      leading: Icon(Icons.delete_outline, color: Colors.red),
                      title: Text('Delete record'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
  Widget line(String a, String z, [bool bold = false, Color? color]) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(a),
        Text(
          z,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : null,
            color: color,
          ),
        ),
      ],
    ),
  );
  IconData activityIcon(SaleKind kind) => switch (kind) {
    SaleKind.sale => Icons.sell_outlined,
    SaleKind.trade => Icons.swap_horiz,
    SaleKind.loan => Icons.handshake_outlined,
  };
  String activityTitle(Sale x) => switch (x.kind) {
    SaleKind.sale =>
      x.grams == 0 ? 'Sold (weight not entered)' : 'Sold ${g(x.grams)}',
    SaleKind.trade => 'Trade ${g(x.grams)}',
    SaleKind.loan =>
      x.grams == 0 ? 'Advance ${dollars(x.cents)}' : 'Loaned ${g(x.grams)}',
  };
  String activitySubtitle(Sale x) {
    final detail = switch (x.kind) {
      SaleKind.sale => '',
      SaleKind.trade => x.note,
      SaleKind.loan => x.note,
    };
    return detail.isEmpty ? date(x.at) : '$detail • ${date(x.at)}';
  }

  Future<void> activity({
    SaleKind initialType = SaleKind.trade,
    Sale? existing,
  }) async {
    final w = TextEditingController(
      text: existing == null ? '' : existing.grams.toStringAsFixed(4),
    );
    final amount = TextEditingController(
      text: existing == null || existing.cents == 0
          ? ''
          : (existing.cents / 100).toStringAsFixed(2),
    );
    final note = TextEditingController(text: existing?.note ?? '');
    Unit u = Unit.grams;
    SaleKind type = initialType;
    await form(existing == null ? 'Record trade or loan' : 'Edit trade/loan', [
      StatefulBuilder(
        builder: (c, set) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<SaleKind>(
              segments: const [
                ButtonSegment(
                  value: SaleKind.trade,
                  label: Text('Trade'),
                  icon: Icon(Icons.swap_horiz),
                ),
                ButtonSegment(
                  value: SaleKind.loan,
                  label: Text('Loan / advance'),
                  icon: Icon(Icons.handshake_outlined),
                ),
              ],
              selected: {type},
              onSelectionChanged: (v) => set(() => type = v.first),
            ),
            const SizedBox(height: 12),
            weight(
              w,
              u,
              (x) => u = x,
              label: type == SaleKind.loan ? 'Weight (optional)' : 'Weight',
            ),
            if (type == SaleKind.trade)
              text(note, 'Traded for', max: 2)
            else ...[
              text(
                amount,
                'Amount owed',
                prefix: '\$',
                type: TextInputType.number,
              ),
              text(note, 'Note (who it was loaned to)', max: 2),
            ],
            FilledButton(
              onPressed: () {
                final n = w.text.trim().isEmpty && type == SaleKind.loan
                    ? 0.0
                    : number(w.text);
                final grams = n == null ? null : toGrams(n, u);
                if (grams == null) {
                  bad(
                    type == SaleKind.loan
                        ? 'Enter a valid weight, or leave it blank.'
                        : 'Enter the weight.',
                  );
                  return;
                }
                if (grams > b.left + (existing?.grams ?? 0) + .00001) {
                  bad('That is more than this batch has available.');
                  return;
                }
                final cents = type == SaleKind.loan ? cash(amount.text) : 0;
                if (type == SaleKind.loan && (cents == null || cents <= 0)) {
                  bad('Enter the amount owed.');
                  return;
                }
                if (type == SaleKind.loan &&
                    existing != null &&
                    cents! < existing.paidCents) {
                  bad(
                    'The loan amount cannot be less than repayments already recorded.',
                  );
                  return;
                }
                if (type == SaleKind.trade && note.text.trim().isEmpty) {
                  bad('Enter what you traded for.');
                  return;
                }
                final record = Sale(
                  grams,
                  cents ?? 0,
                  existing?.at ?? DateTime.now(),
                  kind: type,
                  note: note.text.trim(),
                  paidCents: existing?.paidCents ?? 0,
                );
                if (existing == null) {
                  b.sales.insert(0, record);
                } else {
                  final index = b.sales.indexOf(existing);
                  if (index == -1) return;
                  b.sales[index] = record;
                }
                widget.store.changed();
                Navigator.pop(context);
              },
              child: Text(existing == null ? 'Save record' : 'Save changes'),
            ),
          ],
        ),
      ),
    ]);
  }

  Future<void> sale() async {
    final w = TextEditingController(), p = TextEditingController();
    Unit u = Unit.grams;
    await form('Record a sale', [
      weight(w, u, (x) => u = x, label: 'Weight (optional)'),
      text(p, 'Amount received', prefix: '\$', type: TextInputType.number),
      FilledButton(
        onPressed: () {
          final n = w.text.trim().isEmpty ? 0.0 : number(w.text);
          final v = cash(p.text);
          if (n == null || v == null) {
            bad('Enter the sale price. Weight is optional.');
            return;
          }
          final grams = toGrams(n, u);
          if (grams > b.left + .00001) {
            bad('That is more than this batch has left.');
            return;
          }
          b.sales.insert(0, Sale(grams, v, DateTime.now()));
          widget.store.changed();
          Navigator.pop(context);
        },
        child: const Text('Save sale'),
      ),
    ]);
  }

  Future<void> editSale(Sale sale) async {
    if (sale.kind != SaleKind.sale) {
      await activity(initialType: sale.kind, existing: sale);
      return;
    }
    final w = TextEditingController(text: sale.grams.toStringAsFixed(4));
    final p = TextEditingController(
      text: (sale.cents / 100).toStringAsFixed(2),
    );
    Unit u = Unit.grams;
    await form('Edit sale', [
      weight(w, u, (x) => u = x, label: 'Weight (optional)'),
      text(p, 'Amount received', prefix: '\$', type: TextInputType.number),
      FilledButton(
        onPressed: () {
          final n = w.text.trim().isEmpty ? 0.0 : number(w.text);
          final v = cash(p.text);
          if (n == null || v == null) {
            bad('Enter the sale price. Weight is optional.');
            return;
          }
          final grams = toGrams(n, u);
          final availableWithoutSale = b.left + sale.grams;
          if (grams > availableWithoutSale + .00001) {
            bad('That is more than this batch has available.');
            return;
          }
          final index = b.sales.indexOf(sale);
          if (index == -1) return;
          b.sales[index] = Sale(grams, v, sale.at);
          widget.store.changed();
          Navigator.pop(context);
        },
        child: const Text('Save changes'),
      ),
    ]);
  }

  Future<void> repayLoan(Sale loan) async {
    final owed = loanBalance(loan);
    if (owed <= 0) return;
    final amount = TextEditingController(text: (owed / 100).toStringAsFixed(2));
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Record loan repayment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Still owed: ${dollars(owed)}'),
              const SizedBox(height: 12),
              if (error != null) ...[
                Text(error!, style: TextStyle(color: Colors.red.shade700)),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount repaid',
                  prefixText: '\$',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                final payment = cash(amount.text);
                if (payment == null || payment <= 0) {
                  set(() => error = 'Enter the amount repaid.');
                  return;
                }
                if (payment > owed) {
                  set(() => error = 'That is more than the amount still owed.');
                  return;
                }
                final index = b.sales.indexOf(loan);
                if (index == -1) return;
                b.sales[index] = Sale(
                  loan.grams,
                  loan.cents,
                  loan.at,
                  kind: loan.kind,
                  note: loan.note,
                  person: loan.person,
                  paidCents: loan.paidCents + payment,
                );
                widget.store.changed();
                Navigator.pop(dialogContext);
              },
              child: const Text('Save repayment'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> deleteSale(Sale sale) async {
    final kind = switch (sale.kind) {
      SaleKind.sale => 'sale',
      SaleKind.trade => 'trade',
      SaleKind.loan => 'loan',
    };
    final detail = sale.kind == SaleKind.loan
        ? ' for ${sale.note.isEmpty ? 'the loan' : sale.note}, who owes ${dollars(loanBalance(sale))}'
        : sale.kind == SaleKind.trade
        ? ' for ${sale.note}'
        : ' for ${dollars(sale.cents)}';
    final confirmed = await confirmActivityDelete(
      'Delete this $kind?',
      'This removes the ${g(sale.grams)} $kind$detail. It cannot be undone.',
    );
    if (confirmed != true || !mounted) return;
    b.sales.remove(sale);
    widget.store.changed();
  }

  Future<void> loss({Loss initialType = Loss.waste}) async {
    final w = TextEditingController(), note = TextEditingController();
    Unit u = Unit.grams;
    Loss type = initialType;
    await form('Record product loss', [
      StatefulBuilder(
        builder: (c, set) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<Loss>(
              segments: const [
                ButtonSegment(value: Loss.waste, label: Text('Record waste')),
                ButtonSegment(
                  value: Loss.discrepancy,
                  label: Text('Check remaining weight'),
                ),
              ],
              selected: {type},
              onSelectionChanged: (v) => set(() => type = v.first),
            ),
            const SizedBox(height: 12),
            if (type == Loss.waste)
              weight(w, u, (x) => u = x)
            else ...[
              Text(
                'Sling expects ${g(b.left)} left. Weigh what is actually left, then enter that scale reading below. Enter 0 if you are out of product.',
              ),
              const SizedBox(height: 12),
              weight(w, u, (x) => u = x, label: 'Actual weight left'),
            ],
            text(note, 'Note (optional)', max: 2),
            FilledButton(
              onPressed: () {
                final parsed = double.tryParse(w.text.trim());
                final n = type == Loss.discrepancy && parsed == 0
                    ? 0.0
                    : number(w.text);
                if (n == null) {
                  bad(
                    type == Loss.discrepancy
                        ? 'Enter the remaining weight, or 0 if you are out.'
                        : 'Enter the weight.',
                  );
                  return;
                }
                final grams = toGrams(n, u);
                if (type == Loss.waste) {
                  if (grams > b.left + .00001) {
                    bad('That is more than this batch has left.');
                    return;
                  }
                  b.losses.insert(
                    0,
                    Adjustment(
                      grams,
                      Loss.waste,
                      DateTime.now(),
                      note.text.trim(),
                    ),
                  );
                } else {
                  if (grams > b.left + .00001) {
                    bad(
                      'That is more than Sling currently expects to be left. Edit the purchase if its original weight was wrong.',
                    );
                    return;
                  }
                  final missing = b.left - grams;
                  if (missing < .00001) {
                    bad(
                      'Your scale matches Sling. There is no weighing difference to record.',
                    );
                    return;
                  }
                  b.losses.insert(
                    0,
                    Adjustment(
                      missing,
                      Loss.discrepancy,
                      DateTime.now(),
                      note.text.trim(),
                    ),
                  );
                }
                widget.store.changed();
                Navigator.pop(context);
              },
              child: Text(
                type == Loss.waste ? 'Save waste' : 'Update remaining weight',
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  Future<void> editLoss(Adjustment loss) async {
    final w = TextEditingController(text: loss.grams.toStringAsFixed(4));
    final note = TextEditingController(text: loss.note);
    Unit u = Unit.grams;
    final label = loss.type == Loss.waste
        ? 'Edit waste record'
        : 'Edit weighing difference';
    await form(label, [
      weight(w, u, (x) => u = x),
      text(note, 'Note (optional)', max: 2),
      FilledButton(
        onPressed: () {
          final n = number(w.text);
          if (n == null) {
            bad('Enter the weight.');
            return;
          }
          final grams = toGrams(n, u);
          final availableWithoutLoss = b.left + loss.grams;
          if (grams > availableWithoutLoss + .00001) {
            bad('That is more than this batch has available.');
            return;
          }
          final index = b.losses.indexOf(loss);
          if (index == -1) return;
          b.losses[index] = Adjustment(
            grams,
            loss.type,
            loss.at,
            note.text.trim(),
          );
          widget.store.changed();
          Navigator.pop(context);
        },
        child: const Text('Save changes'),
      ),
    ]);
  }

  Future<void> deleteLoss(Adjustment loss) async {
    final name = loss.type == Loss.waste
        ? 'waste record'
        : 'weighing-difference record';
    final confirmed = await confirmActivityDelete(
      'Delete this $name?',
      'This removes ${g(loss.grams)} from the activity history. It cannot be undone.',
    );
    if (confirmed != true || !mounted) return;
    b.losses.remove(loss);
    widget.store.changed();
  }

  Future<bool?> confirmActivityDelete(String title, String message) =>
      showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep it'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

  Future<void> form(String title, List<Widget> items) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (c) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(c).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(c).textTheme.headlineSmall),
            const SizedBox(height: 18),
            ...items,
          ],
        ),
      ),
    ),
  );
  Widget text(
    TextEditingController c,
    String l, {
    String? prefix,
    TextInputType? type,
    int max = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: c,
      keyboardType: type,
      maxLines: max,
      decoration: InputDecoration(
        labelText: l,
        prefixText: prefix,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  Widget weight(
    TextEditingController c,
    Unit u,
    ValueChanged<Unit> changed, {
    String label = 'Weight',
  }) => StatefulBuilder(
    builder: (context, set) => Row(
      children: [
        Expanded(
          child: text(
            c,
            label,
            type: const TextInputType.numberWithOptions(decimal: true),
          ),
        ),
        const SizedBox(width: 10),
        DropdownButton(
          value: u,
          items: Unit.values
              .map((x) => DropdownMenuItem(value: x, child: Text(x.label)))
              .toList(),
          onChanged: (x) {
            if (x != null) {
              set(() => u = x);
              changed(x);
            }
          },
        ),
      ],
    ),
  );
  void bad(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> editBatch() async {
    final name = TextEditingController(text: b.name);
    final purchaseWeight = TextEditingController(
      text: b.bought.toStringAsFixed(4),
    );
    final cost = TextEditingController(text: (b.cost / 100).toStringAsFixed(2));
    final note = TextEditingController(text: b.note);
    Unit unit = Unit.grams;
    await form('Edit batch', [
      text(name, 'Product / batch label'),
      weight(
        purchaseWeight,
        unit,
        (x) => unit = x,
        label: 'Original purchase weight',
      ),
      text(cost, 'Total amount paid', prefix: '\$', type: TextInputType.number),
      text(note, 'Note (optional)', max: 2),
      FilledButton(
        onPressed: () {
          final enteredWeight = number(purchaseWeight.text);
          final enteredCost = cash(cost.text);
          if (name.text.trim().isEmpty ||
              enteredWeight == null ||
              enteredCost == null) {
            bad('Enter a label, weight, and price.');
            return;
          }
          final grams = toGrams(enteredWeight, unit);
          final alreadyAccountedFor = b.sold + b.waste + b.difference;
          if (grams + .00001 < alreadyAccountedFor) {
            bad(
              'The purchase weight cannot be less than what is already sold or lost.',
            );
            return;
          }
          b.name = name.text.trim();
          b.bought = grams;
          b.cost = enteredCost;
          b.note = note.text.trim();
          widget.store.changed();
          Navigator.pop(context);
        },
        child: const Text('Save changes'),
      ),
    ]);
  }

  Future<void> deleteBatch() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this batch?'),
        content: Text(
          'This removes ${b.name}, including its sales and loss records. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete batch'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      widget.store.remove(b);
      Navigator.pop(context);
    }
  }
}

enum _OverviewAction {
  newPurchase,
  sale,
  editSale,
  deleteSale,
  waste,
  editWaste,
  deleteWaste,
  checkWeight,
  editWeight,
  deleteWeight,
  advance,
  editAdvance,
  deleteAdvance,
  repayment,
  editRepayment,
  edit,
  delete,
  help,
}

enum _BatchAction { edit, delete }

enum _BatchListAction { edit, delete }

enum _AdvanceAction { newAdvance, repay }

enum _SaleAction { edit, repay, delete }

enum _LossAction { edit, delete }

class Help extends StatelessWidget {
  const Help(this.a, this.b, {super.key});
  final String a, b;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          a,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(b),
      ],
    ),
  );
}
