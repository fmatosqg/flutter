import 'package:flutter_tools/src/asset.dart';
import 'package:test/test.dart';


void main() {
  group('Asset name to static variable conversion', () {
    test('Asset name is well behaved', () {
      expect(fieldName('hello_world'), 'helloWorld');
    });

    test('Asset name starts with number', () {
      expect(fieldName('3hello_world'), '_3helloWorld');
    });

    test('Asset name contains space ascii character', () {
      expect(fieldName('hello world'), 'helloWorld');
    });

    test('Asset name contains comma ascii character', () {
      expect(fieldName('hello,world'), 'helloworld');
    });

    test('Asset name contains png extension character', () {
      expect(fieldName('hello_world.png'), 'helloWorld');
    });

    test('Asset name contains dot AND png extension character', () {
      expect(fieldName('hello.world.png'), 'helloWorld');
    });

    test('Asset name contains one invalid ascii character', () {
      expect(fieldName('hello_world!'), 'helloWorld');
    });

    test('Asset name contains some invalid ascii characters', () {
      expect(fieldName('hello_world[@]'), 'helloWorld');
    });
  });
}