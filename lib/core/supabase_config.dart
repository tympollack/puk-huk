// ─────────────────────────────────────────────────────────────────────────────
// Supabase project credentials for Puk Huk
//
// Find these in your Supabase dashboard:
//   https://supabase.com/dashboard/project/<your-project>/settings/api
//
// • SUPABASE_URL     → "Project URL"
// • SUPABASE_ANON_KEY → "anon public" key (safe to embed in mobile apps)
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_dotenv/flutter_dotenv.dart';

abstract final class SupabaseConfig {
  static String get url => dotenv.env['SUPABASE_URL'] ?? 'YOUR_SUPABASE_URL';
  static String get anonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? 'YOUR_SUPABASE_ANON_KEY';
}
