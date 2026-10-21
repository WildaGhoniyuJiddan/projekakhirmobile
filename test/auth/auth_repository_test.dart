import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/models/auth_models.dart';
import 'package:worthbang/services/auth/auth_repository.dart';
import 'package:worthbang/services/auth/token_storage.dart';

/// Kontrak AuthRepository versi Supabase Auth (full-Dart).
///
/// Alur login/register butuh proyek Supabase hidup sehingga diuji
/// manual/E2E (lihat SUPABASE_SETUP.md). Yang bisa diuji tanpa server:
/// perilaku cache lokal (cermin sesi di TokenStorage) yang dipakai
/// gerbang biometrik dan pemulihan profil.
void main() {
  late TokenStorage storage;
  late AuthRepository repo;

  setUp(() {
    storage = TokenStorage(MemorySecureKv());
    repo = AuthRepository(storage: storage);
  });

  group('AuthRepository — cache lokal', () {
    test('currentUser null sebelum ada sesi tersimpan', () async {
      expect(await repo.currentUser(), isNull);
    });

    test('updateCachedUser menyimpan profil (id uuid string)', () async {
      const user = AppUser(
        id: '9b2f4b7e-1c2a-4e5f-9a8b-0123456789ab',
        name: 'Dan',
        email: 'dan@example.com',
      );
      await repo.updateCachedUser(user);
      final cached = await repo.currentUser();
      expect(cached?.id, user.id);
      expect(cached?.name, 'Dan');
      expect(cached?.email, 'dan@example.com');
    });

    test('logout membersihkan cermin token + profil', () async {
      await storage.saveTokens(
        accessToken: 'access-x',
        refreshToken: 'refresh-x',
      );
      await repo.updateCachedUser(
        const AppUser(id: 'u1', name: 'Dan', email: 'dan@example.com'),
      );
      await repo.logout();
      expect(await storage.readAccessToken(), isNull);
      expect(await storage.readRefreshToken(), isNull);
      expect(await repo.currentUser(), isNull);
    });
  });
}
