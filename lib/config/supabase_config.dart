/// Konfigurasi Supabase — versi full-Dart (projekakhirmobile).
///
/// Isi lewat --dart-define saat build/run:
///   flutter run --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=<anon-key>
///
/// Anon key AMAN dibundel di APK: seluruh proteksi data ada di
/// Row Level Security (lihat supabase/migrations/). Yang TIDAK BOLEH
/// masuk APK: service-role key & GEMINI_API_KEY (itu di Edge Function).
library;

const String supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://kvubnpujxiiqhpcrzlso.supabase.co',
);

const String supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt2dWJucHVqeGlpcWhwY3J6bHNvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI0OTU5OTIsImV4cCI6MjEwODA3MTk5Mn0.2TQLLOBfcicc_XHwzDoYHz6K8PC9-sEsADr6syQl24U',
);

bool get supabaseConfigured => supabaseAnonKey != 'YOUR-ANON-KEY';
