import 'package:lumide_discord/lumide_discord.dart';
import 'package:test/test.dart';

void main() {
  group('PresenceSettings.fromValues', () {
    test('uses the defaults for missing values', () {
      final settings = PresenceSettings.fromValues(const {});
      expect(settings.enabled, isTrue);
      expect(settings.applicationId, PresenceSettings.defaultApplicationId);
      expect(settings.showFileName, isTrue);
      expect(settings.showProjectName, isTrue);
      expect(settings.showLanguage, isTrue);
      expect(settings.showElapsedTime, isTrue);
      expect(settings.idleMinutes, 5);
      expect(settings.clearWhenIdle, isFalse);
      expect(settings.privacyMode, isFalse);
    });

    test('reads every key', () {
      final settings = PresenceSettings.fromValues(const {
        PresenceSettings.enabledKey: false,
        PresenceSettings.applicationIdKey: '123456789012345678',
        PresenceSettings.showFileNameKey: false,
        PresenceSettings.showProjectNameKey: false,
        PresenceSettings.showLanguageKey: false,
        PresenceSettings.showElapsedTimeKey: false,
        PresenceSettings.idleMinutesKey: 15,
        PresenceSettings.clearWhenIdleKey: true,
        PresenceSettings.privacyModeKey: true,
      });
      expect(settings.enabled, isFalse);
      expect(settings.applicationId, '123456789012345678');
      expect(settings.showFileName, isFalse);
      expect(settings.showProjectName, isFalse);
      expect(settings.showLanguage, isFalse);
      expect(settings.showElapsedTime, isFalse);
      expect(settings.idleMinutes, 15);
      expect(settings.clearWhenIdle, isTrue);
      expect(settings.privacyMode, isTrue);
    });

    test('falls back to the defaults for wrongly typed values', () {
      final settings = PresenceSettings.fromValues(const {
        PresenceSettings.enabledKey: 'yes',
        PresenceSettings.applicationIdKey: 42,
        PresenceSettings.idleMinutesKey: 'ten',
      });
      expect(settings.enabled, isTrue);
      expect(settings.applicationId, PresenceSettings.defaultApplicationId);
      expect(settings.idleMinutes, 5);
    });

    test('trims the application ID', () {
      final settings = PresenceSettings.fromValues(const {
        PresenceSettings.applicationIdKey: '  123  ',
      });
      expect(settings.applicationId, '123');
    });

    test("uses the plugin's application when the ID is left empty", () {
      for (final empty in ['', '   ']) {
        expect(
          PresenceSettings.fromValues({
            PresenceSettings.applicationIdKey: empty,
          }).applicationId,
          PresenceSettings.defaultApplicationId,
        );
      }
    });

    test('accepts whole numbers stored as doubles and clamps negatives', () {
      expect(
        PresenceSettings.fromValues(const {
          PresenceSettings.idleMinutesKey: 10.0,
        }).idleMinutes,
        10,
      );
      expect(
        PresenceSettings.fromValues(const {
          PresenceSettings.idleMinutesKey: -3,
        }).idleMinutes,
        0,
      );
    });

    group('buttons', () {
      PresenceSettings read(Map<String, Object?> values) =>
          PresenceSettings.fromValues(values);

      test('shows the website and Lumide Discord by default', () {
        expect(read(const {}).buttons, [
          PresenceSettings.websiteButton,
          PresenceSettings.discordButton,
        ]);
      });

      test('can be hidden', () {
        expect(
          read(const {PresenceSettings.showButtonsKey: false}).buttons,
          isEmpty,
        );
      });

      test('puts your own button in place of Lumide Discord', () {
        final settings = read(const {
          PresenceSettings.customButtonLabelKey: ' View on GitHub ',
          PresenceSettings.customButtonUrlKey: 'https://github.com/me/app',
        });
        expect(settings.buttons, [
          PresenceSettings.websiteButton,
          (label: 'View on GitHub', url: 'https://github.com/me/app'),
        ]);
      });

      test('ignores your button without text or a web address', () {
        for (final (label, url) in [
          ('', 'https://github.com/me/app'),
          ('GitHub', ''),
          ('GitHub', 'github.com/me/app'),
          ('GitHub', 'javascript:alert(1)'),
          ('GitHub', 'https://'),
          ('GitHub', 'https://example.com/${'a' * 600}'),
        ]) {
          expect(
            read({
              PresenceSettings.customButtonLabelKey: label,
              PresenceSettings.customButtonUrlKey: url,
            }).customButton,
            isNull,
            reason: '$label $url',
          );
        }
      });

      test("shortens labels to Discord's 32 characters", () {
        final label = read({
          PresenceSettings.customButtonLabelKey: 'x' * 40,
          PresenceSettings.customButtonUrlKey: 'https://example.com',
        }).customButton!.label;
        expect(label, hasLength(32));
        expect(label, endsWith('…'));
      });

      test("Lumide's buttons fit Discord's limits", () {
        for (final button in [
          PresenceSettings.websiteButton,
          PresenceSettings.discordButton,
        ]) {
          expect(button.label.length, lessThanOrEqualTo(32));
          expect(Uri.parse(button.url).isScheme('https'), isTrue);
        }
      });
    });

    test('lists every key once', () {
      expect(PresenceSettings.keys.toSet(), hasLength(12));
      expect(PresenceSettings.keys, everyElement(startsWith('discordPresence.')));
    });
  });
}
