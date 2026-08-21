import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/legal/legal_urls.dart';

void main() {
  group('LegalUrls', () {
    test('contact URL is valid HTTPS', () {
      final uri = Uri.parse(LegalUrls.contact);
      expect(uri.isAbsolute, isTrue);
      expect(uri.scheme, 'https');
      expect(uri.host, isNotEmpty);
      expect(uri.path, contains('contact.html'));
    });

    test('privacy URL is valid HTTPS', () {
      final uri = Uri.parse(LegalUrls.privacyPolicy);
      expect(uri.isAbsolute, isTrue);
      expect(uri.scheme, 'https');
      expect(uri.host, isNotEmpty);
    });

    test('terms URL is valid HTTPS', () {
      final uri = Uri.parse(LegalUrls.termsOfService);
      expect(uri.isAbsolute, isTrue);
      expect(uri.scheme, 'https');
      expect(uri.host, isNotEmpty);
    });

    test('all URLs are configured (not placeholders)', () {
      expect(LegalUrls.isConfigured, isTrue);
    });
  });

  group('Contact page — platform icons', () {
    late String contactHtml;

    setUpAll(() {
      final file = File('docs/legal/contact.html');
      contactHtml = file.readAsStringSync();
    });

    test('WhatsApp icon exists (fa-whatsapp)', () {
      expect(contactHtml, contains('fa-whatsapp'));
    });

    test('Instagram icon exists (fa-instagram)', () {
      expect(contactHtml, contains('fa-instagram'));
    });

    test('GitHub icon exists (fa-github)', () {
      expect(contactHtml, contains('fa-github'));
    });

    test('LinkedIn icon exists (fa-linkedin-in)', () {
      expect(contactHtml, contains('fa-linkedin-in'));
    });

    test('X icon exists (fa-x-twitter)', () {
      expect(contactHtml, contains('fa-x-twitter'));
    });

    test('Email icon exists (fa-envelope)', () {
      expect(contactHtml, contains('fa-envelope'));
    });

    test('Phone icon exists (fa-phone)', () {
      expect(contactHtml, contains('fa-phone'));
    });

    test('all icons have aria-hidden for screen readers', () {
      expect(contactHtml, contains('aria-hidden="true"'));
    });
  });

  group('Contact page — accessible labels', () {
    late String contactHtml;

    setUpAll(() {
      final file = File('docs/legal/contact.html');
      contactHtml = file.readAsStringSync();
    });

    test('WhatsApp has aria-label', () {
      expect(contactHtml, contains('aria-label="WhatsApp"'));
    });

    test('Instagram has aria-label', () {
      expect(contactHtml, contains('aria-label="Instagram"'));
    });

    test('GitHub has aria-label', () {
      expect(contactHtml, contains('aria-label="GitHub"'));
    });

    test('LinkedIn has aria-label', () {
      expect(contactHtml, contains('aria-label="LinkedIn"'));
    });

    test('X has aria-label', () {
      expect(contactHtml, contains('aria-label="X"'));
    });

    test('Email has aria-label', () {
      expect(contactHtml, contains('aria-label="Email"'));
    });

    test('Phone has aria-label', () {
      expect(contactHtml, contains('aria-label="Call"'));
    });
  });

  group('Contact page — URLs', () {
    late String contactHtml;

    setUpAll(() {
      final file = File('docs/legal/contact.html');
      contactHtml = file.readAsStringSync();
    });

    test('Instagram URL is fans.of.caleb', () {
      expect(contactHtml, contains('https://www.instagram.com/fans.of.caleb/'));
    });

    test('old Instagram URL (sxmplycaleb) is absent', () {
      expect(contactHtml, isNot(contains('instagram.com/sxmplycaleb')));
    });

    test('WhatsApp URL is correct', () {
      expect(contactHtml, contains('https://wa.me/254790321533'));
    });

    test('phone URL is correct', () {
      expect(contactHtml, contains('tel:+254790321533'));
    });

    test('email URL is correct', () {
      expect(contactHtml, contains('mailto:support.omanutro@gmail.com'));
    });

    test('LinkedIn URL is correct', () {
      expect(contactHtml, contains('linkedin.com/in/caleb-ong-au-573219333'));
    });

    test('X URL is correct', () {
      expect(contactHtml, contains('x.com/sxmplycaleb'));
    });

    test('GitHub URL is correct', () {
      expect(contactHtml, contains('github.com/sxmplycaleb'));
    });
  });

  group('Contact page — branding', () {
    late String contactHtml;

    setUpAll(() {
      final file = File('docs/legal/contact.html');
      contactHtml = file.readAsStringSync();
    });

    test('page contains TurtleKing header', () {
      expect(contactHtml, contains('<h1>TurtleKing</h1>'));
    });

    test('page contains TurtleKing emblem', () {
      expect(contactHtml, contains('turtle_king_emblem.png'));
    });

    test('page contains copyright', () {
      expect(contactHtml, contains('&copy; 2026 TurtleKing'));
    });

    test('social links have handle details', () {
      expect(contactHtml, contains('@fans.of.caleb'));
      expect(contactHtml, contains('@sxmplycaleb'));
    });

    test('platform-specific CSS classes exist', () {
      expect(contactHtml, contains('social-link--instagram'));
      expect(contactHtml, contains('social-link--linkedin'));
      expect(contactHtml, contains('social-link--x'));
      expect(contactHtml, contains('social-link--github'));
      expect(contactHtml, contains('contact-link--whatsapp'));
      expect(contactHtml, contains('contact-link--phone'));
      expect(contactHtml, contains('contact-link--email'));
    });
  });

  group('CSS — platform brand colors', () {
    late String css;

    setUpAll(() {
      final file = File('docs/legal/css/style.css');
      css = file.readAsStringSync();
    });

    test('navy color variable is defined', () {
      expect(css, contains('--navy: #0B263C'));
    });

    test('gold color variable is defined', () {
      expect(css, contains('--gold: #C5A44E'));
    });

    test('header-logo class exists', () {
      expect(css, contains('.header-logo'));
    });

    test('contact-link styles exist', () {
      expect(css, contains('.contact-link'));
    });

    test('social-link styles exist', () {
      expect(css, contains('.social-link'));
    });

    test('Instagram uses gradient branding', () {
      expect(css, contains('social-link--instagram'));
      expect(css, contains('linear-gradient'));
    });

    test('LinkedIn uses brand blue #0077B5', () {
      expect(css, contains('social-link--linkedin'));
      expect(css, contains('#0077B5'));
    });

    test('X uses black branding', () {
      expect(css, contains('social-link--x'));
      expect(css, contains('#000000'));
    });

    test('GitHub uses dark branding', () {
      expect(css, contains('social-link--github'));
      expect(css, contains('#24292e'));
    });

    test('WhatsApp icon uses green', () {
      expect(css, contains('contact-link--whatsapp'));
      expect(css, contains('#25D366'));
    });

    test('email icon uses red', () {
      expect(css, contains('contact-link--email'));
      expect(css, contains('#EA4335'));
    });

    test('social-handle class exists', () {
      expect(css, contains('.social-handle'));
    });

    test('social-info class exists', () {
      expect(css, contains('.social-info'));
    });
  });
}
