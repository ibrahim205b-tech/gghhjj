/// Database schema and versioned migrations for Generator OS.
///
/// Design principles:
/// * All primary keys are TEXT ids (UUID or deterministic ids derived from
///   the source document) so records created offline on several devices can
///   be merged without collisions.
/// * Money is stored as INTEGER Iraqi dinars. Fuel is stored as INTEGER
///   millilitres. No floating point for accounting.
/// * Financial facts (journal entries/lines, payments, invoice adjustments,
///   audit logs, fuel movements) are append-only. Triggers abort any UPDATE or
///   DELETE so corrections must be made with reversing entries.
library;

class Migration {
  final int version;
  final String name;
  final List<String> statements;
  const Migration(this.version, this.name, this.statements);
}

/// Tables whose rows may be edited after creation (master data). Sync uses
/// last-writer-wins by *server arrival order* for these.
const mutableTables = <String>[
  'generators',
  'branches',
  'areas',
  'cabinets',
  'lines',
  'subscribers',
  'users',
  'roles',
  'role_permissions',
  'user_generators',
  'collectors',
  'collector_assignments',
  'cashboxes',
  'suppliers',
  'employees',
  'billing_periods',
  'maintenance_plans',
  'maintenance_records',
  'fault_records',
  'complaints',
  'generator_runs',
  'iot_devices',
];

/// Append-only tables. Sync merges them as a set union (INSERT OR IGNORE).
const immutableTables = <String>[
  'accounts',
  'journal_entries',
  'journal_lines',
  'invoices',
  'invoice_adjustments',
  'payments',
  'collector_handovers',
  'expenses',
  'fuel_purchases',
  'fuel_consumptions',
  'fuel_dips',
  'cash_closings',
  'subscriber_events',
  'complaint_replies',
  'audit_logs',
  'sensor_readings',
];

String _immutable(String table) => '''
CREATE TRIGGER trg_${table}_no_delete BEFORE DELETE ON $table
BEGIN SELECT RAISE(ABORT, 'IMMUTABLE_RECORD'); END;
''';

/// Updates are blocked except while the sync engine replaces a duplicate of
/// the same business document with the server's canonical copy (flag set in
/// `local_meta` inside the sync transaction only). Deletes are always blocked.
String _immutableUpdate(String table) => '''
CREATE TRIGGER trg_${table}_no_update BEFORE UPDATE ON $table
WHEN NOT EXISTS (SELECT 1 FROM local_meta WHERE key = 'sync_override')
BEGIN SELECT RAISE(ABORT, 'IMMUTABLE_RECORD'); END;
''';

final migrations = <Migration>[
  Migration(1, 'initial', [
    // ---------------------------------------------------------------- meta
    '''CREATE TABLE settings(
      key TEXT PRIMARY KEY, value TEXT, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1)''',
    '''CREATE TABLE local_meta(key TEXT PRIMARY KEY, value TEXT)''',

    // ------------------------------------------------------ organisation
    '''CREATE TABLE generators(
      id TEXT PRIMARY KEY, name TEXT NOT NULL, code TEXT, capacity_kva INTEGER,
      province TEXT, address TEXT, default_amp_price INTEGER NOT NULL DEFAULT 0,
      fuel_low_threshold_ml INTEGER NOT NULL DEFAULT 200000,
      active INTEGER NOT NULL DEFAULT 1, notes TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1)''',
    '''CREATE TABLE branches(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL REFERENCES generators(id),
      name TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1)''',
    '''CREATE TABLE areas(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL REFERENCES generators(id),
      name TEXT NOT NULL, province TEXT, district TEXT, active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1)''',
    '''CREATE TABLE cabinets(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL REFERENCES generators(id),
      area_id TEXT REFERENCES areas(id), code TEXT NOT NULL, location TEXT,
      max_amps INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1)''',
    '''CREATE TABLE lines(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL REFERENCES generators(id),
      cabinet_id TEXT REFERENCES cabinets(id), code TEXT NOT NULL,
      max_amps INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1)''',

    // ---------------------------------------------------------- security
    '''CREATE TABLE roles(
      id TEXT PRIMARY KEY, name TEXT NOT NULL, is_system INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1)''',
    '''CREATE TABLE role_permissions(
      id TEXT PRIMARY KEY, role_id TEXT NOT NULL REFERENCES roles(id), permission TEXT NOT NULL,
      granted INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1,
      UNIQUE(role_id, permission))''',
    '''CREATE TABLE users(
      id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE, full_name TEXT NOT NULL,
      phone TEXT, role_id TEXT NOT NULL REFERENCES roles(id), password_hash TEXT NOT NULL,
      all_generators INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1,
      failed_attempts INTEGER NOT NULL DEFAULT 0, locked_until TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1)''',
    '''CREATE TABLE user_generators(
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id),
      generator_id TEXT NOT NULL REFERENCES generators(id), active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1,
      UNIQUE(user_id, generator_id))''',
    '''CREATE TABLE devices(
      id TEXT PRIMARY KEY, name TEXT, first_seen TEXT NOT NULL, last_seen TEXT NOT NULL,
      revoked INTEGER NOT NULL DEFAULT 0)''',
    '''CREATE TABLE sessions(
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL, device_id TEXT NOT NULL,
      created_at TEXT NOT NULL, last_active TEXT NOT NULL, revoked INTEGER NOT NULL DEFAULT 0)''',
    '''CREATE TABLE audit_logs(
      id TEXT PRIMARY KEY, at TEXT NOT NULL, user_id TEXT, device_id TEXT,
      generator_id TEXT, action TEXT NOT NULL, entity TEXT, entity_id TEXT, details TEXT)''',
    _immutable('audit_logs'),
    _immutableUpdate('audit_logs'),
    'CREATE INDEX idx_audit_at ON audit_logs(at)',

    // ------------------------------------------------------ subscribers
    '''CREATE TABLE subscribers(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL REFERENCES generators(id),
      account_no TEXT NOT NULL, full_name TEXT NOT NULL, phone TEXT, phone2 TEXT,
      meter_no TEXT, province TEXT, area_id TEXT REFERENCES areas(id), mahalla TEXT,
      alley TEXT, house TEXT, landmark TEXT, lat REAL, lng REAL,
      cabinet_id TEXT REFERENCES cabinets(id), line_id TEXT REFERENCES lines(id),
      amps INTEGER NOT NULL, amp_price INTEGER NOT NULL,
      subscription_type TEXT NOT NULL DEFAULT 'normal',
      start_date TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'active',
      connected INTEGER NOT NULL DEFAULT 1, notes TEXT, meter_photo TEXT,
      qr_token TEXT NOT NULL,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1,
      UNIQUE(generator_id, account_no))''',
    'CREATE INDEX idx_sub_name ON subscribers(full_name)',
    'CREATE INDEX idx_sub_phone ON subscribers(phone)',
    'CREATE INDEX idx_sub_gen ON subscribers(generator_id, status)',
    // History of every change to a subscriber (transfer, stop, amps change...).
    '''CREATE TABLE subscriber_events(
      id TEXT PRIMARY KEY, subscriber_id TEXT NOT NULL REFERENCES subscribers(id),
      generator_id TEXT NOT NULL, at TEXT NOT NULL, kind TEXT NOT NULL,
      from_value TEXT, to_value TEXT, reason TEXT, user_id TEXT)''',
    _immutable('subscriber_events'),
    _immutableUpdate('subscriber_events'),

    // ---------------------------------------------------------- ledger
    '''CREATE TABLE accounts(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL REFERENCES generators(id),
      code TEXT NOT NULL, name TEXT NOT NULL, type TEXT NOT NULL,
      created_at TEXT NOT NULL, UNIQUE(generator_id, code))''',
    _immutable('accounts'),
    '''CREATE TABLE journal_entries(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL REFERENCES generators(id),
      entry_date TEXT NOT NULL, description TEXT NOT NULL,
      source_type TEXT NOT NULL, source_id TEXT, reverses_id TEXT,
      created_at TEXT NOT NULL, created_by TEXT, device_id TEXT)''',
    _immutable('journal_entries'),
    _immutableUpdate('journal_entries'),
    'CREATE INDEX idx_je_gen_date ON journal_entries(generator_id, entry_date)',
    'CREATE UNIQUE INDEX idx_je_reverses ON journal_entries(reverses_id) WHERE reverses_id IS NOT NULL',
    '''CREATE TABLE journal_lines(
      id TEXT PRIMARY KEY, entry_id TEXT NOT NULL REFERENCES journal_entries(id),
      generator_id TEXT NOT NULL, account_id TEXT NOT NULL REFERENCES accounts(id),
      debit INTEGER NOT NULL DEFAULT 0, credit INTEGER NOT NULL DEFAULT 0,
      party_type TEXT, party_id TEXT, entry_date TEXT NOT NULL, memo TEXT,
      CHECK(debit >= 0 AND credit >= 0 AND (debit = 0 OR credit = 0)))''',
    _immutable('journal_lines'),
    _immutableUpdate('journal_lines'),
    'CREATE INDEX idx_jl_account ON journal_lines(account_id, entry_date)',
    'CREATE INDEX idx_jl_party ON journal_lines(party_type, party_id)',
    'CREATE INDEX idx_jl_entry ON journal_lines(entry_id)',

    // --------------------------------------------------------- billing
    '''CREATE TABLE billing_periods(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL, period TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'open', closed_at TEXT, closed_by TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1,
      UNIQUE(generator_id, period))''',
    // Invoice id is deterministic: inv:<subscriber>:<period>. A second invoice
    // for the same subscriber/month is therefore impossible, even across
    // devices working offline.
    '''CREATE TABLE invoices(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL, subscriber_id TEXT NOT NULL REFERENCES subscribers(id),
      period TEXT NOT NULL, issue_date TEXT NOT NULL, amps INTEGER NOT NULL,
      amp_price INTEGER NOT NULL, gross INTEGER NOT NULL, discount INTEGER NOT NULL DEFAULT 0,
      discount_reason TEXT, net INTEGER NOT NULL, created_at TEXT NOT NULL, created_by TEXT,
      UNIQUE(subscriber_id, period))''',
    _immutable('invoices'),
    _immutableUpdate('invoices'),
    'CREATE INDEX idx_inv_gen_period ON invoices(generator_id, period)',
    '''CREATE TABLE invoice_adjustments(
      id TEXT PRIMARY KEY, invoice_id TEXT NOT NULL REFERENCES invoices(id),
      generator_id TEXT NOT NULL, subscriber_id TEXT NOT NULL,
      kind TEXT NOT NULL, amount INTEGER NOT NULL, reason TEXT NOT NULL,
      created_at TEXT NOT NULL, created_by TEXT)''',
    _immutable('invoice_adjustments'),
    _immutableUpdate('invoice_adjustments'),

    // ------------------------------------------------------ collection
    '''CREATE TABLE collectors(
      id TEXT PRIMARY KEY, user_id TEXT REFERENCES users(id), full_name TEXT NOT NULL,
      phone TEXT, photo TEXT, commission_percent INTEGER NOT NULL DEFAULT 0,
      monthly_salary INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1)''',
    '''CREATE TABLE collector_assignments(
      id TEXT PRIMARY KEY, collector_id TEXT NOT NULL REFERENCES collectors(id),
      generator_id TEXT NOT NULL, area_id TEXT, cabinet_id TEXT, active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1)''',
    '''CREATE TABLE cashboxes(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL, name TEXT NOT NULL,
      account_id TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1)''',
    '''CREATE TABLE payments(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL, subscriber_id TEXT NOT NULL REFERENCES subscribers(id),
      amount INTEGER NOT NULL CHECK(amount > 0), method TEXT NOT NULL DEFAULT 'cash',
      collector_id TEXT, cashbox_id TEXT, receipt_no TEXT NOT NULL, paid_at TEXT NOT NULL,
      pay_date TEXT NOT NULL, notes TEXT, created_by TEXT, device_id TEXT,
      reversal_of TEXT)''',
    // Receipt numbers are for display; the payment id is the identity.
    'CREATE INDEX idx_pay_receipt ON payments(receipt_no)',
    _immutable('payments'),
    _immutableUpdate('payments'),
    'CREATE UNIQUE INDEX idx_pay_reversal ON payments(reversal_of) WHERE reversal_of IS NOT NULL',
    'CREATE INDEX idx_pay_sub ON payments(subscriber_id)',
    'CREATE INDEX idx_pay_date ON payments(generator_id, pay_date)',
    '''CREATE TABLE collector_handovers(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL, collector_id TEXT NOT NULL,
      cashbox_id TEXT NOT NULL, amount INTEGER NOT NULL CHECK(amount > 0),
      handover_date TEXT NOT NULL, notes TEXT, created_at TEXT NOT NULL, created_by TEXT)''',
    _immutable('collector_handovers'),
    _immutableUpdate('collector_handovers'),
    '''CREATE TABLE cash_closings(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL, cashbox_id TEXT NOT NULL,
      close_date TEXT NOT NULL, expected INTEGER NOT NULL, counted INTEGER NOT NULL,
      difference INTEGER NOT NULL, notes TEXT, created_at TEXT NOT NULL, created_by TEXT,
      UNIQUE(cashbox_id, close_date))''',
    _immutable('cash_closings'),
    _immutableUpdate('cash_closings'),

    // ------------------------------------------------- expenses & parties
    '''CREATE TABLE suppliers(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL, name TEXT NOT NULL, phone TEXT,
      kind TEXT NOT NULL DEFAULT 'fuel', notes TEXT, active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1)''',
    '''CREATE TABLE employees(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL, full_name TEXT NOT NULL, phone TEXT,
      job TEXT, monthly_salary INTEGER NOT NULL DEFAULT 0, user_id TEXT,
      active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1)''',
    '''CREATE TABLE expenses(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL, category TEXT NOT NULL,
      amount INTEGER NOT NULL CHECK(amount > 0), expense_date TEXT NOT NULL,
      pay_method TEXT NOT NULL, cashbox_id TEXT, supplier_id TEXT, employee_id TEXT,
      description TEXT, reference TEXT, created_at TEXT NOT NULL, created_by TEXT)''',
    _immutable('expenses'),
    _immutableUpdate('expenses'),
    'CREATE INDEX idx_exp_date ON expenses(generator_id, expense_date)',

    // ------------------------------------------------------------- fuel
    '''CREATE TABLE fuel_purchases(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL, supplier_id TEXT,
      purchase_date TEXT NOT NULL, quantity_ml INTEGER NOT NULL CHECK(quantity_ml > 0),
      price_per_liter INTEGER NOT NULL, total INTEGER NOT NULL, pay_method TEXT NOT NULL,
      cashbox_id TEXT, invoice_no TEXT, notes TEXT, created_at TEXT NOT NULL, created_by TEXT)''',
    _immutable('fuel_purchases'),
    _immutableUpdate('fuel_purchases'),
    // source: manual (typed by a person) or sensor (from a connected device).
    '''CREATE TABLE fuel_consumptions(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL, consumption_date TEXT NOT NULL,
      quantity_ml INTEGER NOT NULL CHECK(quantity_ml > 0), cost INTEGER NOT NULL,
      run_hours_x100 INTEGER, source TEXT NOT NULL DEFAULT 'manual', notes TEXT,
      created_at TEXT NOT NULL, created_by TEXT)''',
    _immutable('fuel_consumptions'),
    _immutableUpdate('fuel_consumptions'),
    // Physical tank measurement (dip stick / gauge) to compare with the book.
    '''CREATE TABLE fuel_dips(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL, measured_at TEXT NOT NULL,
      quantity_ml INTEGER NOT NULL, source TEXT NOT NULL DEFAULT 'manual', notes TEXT,
      created_at TEXT NOT NULL, created_by TEXT)''',
    _immutable('fuel_dips'),

    // --------------------------------------------------- operations
    '''CREATE TABLE generator_runs(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL, started_at TEXT NOT NULL,
      stopped_at TEXT, stop_reason TEXT, grid_outage INTEGER NOT NULL DEFAULT 0, notes TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1)''',
    'CREATE INDEX idx_runs_gen ON generator_runs(generator_id, started_at)',
    '''CREATE TABLE maintenance_plans(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL, kind TEXT NOT NULL,
      interval_days INTEGER, interval_hours INTEGER, last_done_date TEXT,
      last_done_hours_x100 INTEGER, active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1)''',
    '''CREATE TABLE maintenance_records(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL, kind TEXT NOT NULL,
      done_date TEXT NOT NULL, technician TEXT, parts TEXT, parts_cost INTEGER NOT NULL DEFAULT 0,
      labor_cost INTEGER NOT NULL DEFAULT 0, next_due_date TEXT, notes TEXT, expense_id TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1)''',
    '''CREATE TABLE fault_records(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL, title TEXT NOT NULL, description TEXT,
      severity TEXT NOT NULL, occurred_at TEXT NOT NULL, fixed_at TEXT, technician TEXT,
      repair_cost INTEGER NOT NULL DEFAULT 0, parts TEXT, attachments TEXT,
      status TEXT NOT NULL DEFAULT 'open', expense_id TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1)''',

    // -------------------------------------------------- service desk
    '''CREATE TABLE complaints(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL, ticket_no TEXT NOT NULL UNIQUE,
      subscriber_id TEXT, category TEXT NOT NULL, priority TEXT NOT NULL DEFAULT 'normal',
      title TEXT NOT NULL, body TEXT, assignee TEXT, status TEXT NOT NULL DEFAULT 'open',
      opened_at TEXT NOT NULL, resolved_at TEXT, archived INTEGER NOT NULL DEFAULT 0,
      attachments TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1)''',
    '''CREATE TABLE complaint_replies(
      id TEXT PRIMARY KEY, complaint_id TEXT NOT NULL REFERENCES complaints(id),
      at TEXT NOT NULL, user_id TEXT, body TEXT NOT NULL)''',
    _immutable('complaint_replies'),

    // ------------------------------------------- notifications (local)
    '''CREATE TABLE notifications(
      id TEXT PRIMARY KEY, generator_id TEXT, kind TEXT NOT NULL, severity TEXT NOT NULL,
      title TEXT NOT NULL, body TEXT, created_at TEXT NOT NULL, read INTEGER NOT NULL DEFAULT 0,
      dedupe_key TEXT UNIQUE)''',

    // --------------------------------------------------------- devices
    '''CREATE TABLE iot_devices(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL, name TEXT NOT NULL,
      protocol TEXT NOT NULL, endpoint TEXT, last_seen TEXT, active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1)''',
    '''CREATE TABLE sensor_readings(
      id TEXT PRIMARY KEY, generator_id TEXT NOT NULL, device_id TEXT NOT NULL,
      at TEXT NOT NULL, metric TEXT NOT NULL, value REAL NOT NULL)''',
    _immutable('sensor_readings'),

    // ------------------------------------------------------------ sync
    '''CREATE TABLE sync_queue(
      seq INTEGER PRIMARY KEY AUTOINCREMENT, idempotency_key TEXT NOT NULL UNIQUE,
      table_name TEXT NOT NULL, row_id TEXT NOT NULL, payload TEXT NOT NULL,
      created_at TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending',
      attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT)''',
    'CREATE INDEX idx_sync_status ON sync_queue(status, seq)',
    '''CREATE TABLE sync_log(
      id INTEGER PRIMARY KEY AUTOINCREMENT, at TEXT NOT NULL, direction TEXT NOT NULL,
      ok INTEGER NOT NULL, count INTEGER NOT NULL DEFAULT 0, message TEXT)''',
    '''CREATE TABLE sync_conflicts(
      id INTEGER PRIMARY KEY AUTOINCREMENT, at TEXT NOT NULL, table_name TEXT NOT NULL,
      row_id TEXT NOT NULL, local_payload TEXT, remote_payload TEXT, resolution TEXT NOT NULL)''',
  ]),
];

int get latestSchemaVersion => migrations.last.version;
