import { Intunix } from '../src';
import { calls } from './react-native-mock';

// No @types/node in this package; the jest runtime provides require.
declare const require: (m: string) => any;
const nodeRequire = require;

beforeEach(() => { calls.length = 0; });

test('each call maps to its native method with defaults filled in', () => {
  Intunix.initialize('ck_1', { registerAll: true });
  Intunix.identify('u1');
  Intunix.track('checkout', { total: 49.5 });
  Intunix.screen('Home');
  Intunix.setContext({ store: 'dhaka' });
  Intunix.clearContext();
  Intunix.showForm('nps');
  Intunix.showForm('nps', { order: 7 });
  Intunix.register('nps');
  Intunix.unregister('nps');
  Intunix.reset();
  expect(calls).toEqual([
    ['initialize', ['ck_1', { registerAll: true }]],
    ['identify', ['u1', {}]],
    ['track', ['checkout', { total: 49.5 }]],
    ['screen', ['Home']],
    ['setContext', [{ store: 'dhaka' }]],
    ['setContext', [null]],
    ['showForm', ['nps', null]],
    ['showForm', ['nps', { order: 7 }]],
    ['register', ['nps']],
    ['unregister', ['nps']],
    ['reset', []],
  ]);
});

test('theme goes through init and setTheme', () => {
  Intunix.initialize('ck_1', { theme: 'dark' });
  Intunix.setTheme('light');
  expect(calls).toEqual([
    ['initialize', ['ck_1', { theme: 'dark' }]],
    ['setTheme', ['light']],
  ]);
});

test('locale goes through init and setLocale', () => {
  Intunix.initialize('ck_1', { locale: 'bn' });
  Intunix.setLocale('ar');
  expect(calls).toEqual([['initialize', ['ck_1', { locale: 'bn' }]], ['setLocale', ['ar']]]);
});

test('every native method is declared by both bridges', () => {
  const fs = nodeRequire('fs');
  const m = fs.readFileSync('ios/IntunixModule.m', 'utf8');
  const kt = fs.readFileSync('android/src/main/java/com/intunix/reactnative/IntunixModule.kt', 'utf8');
  for (const name of ['initialize', 'identify', 'reset', 'track', 'screen', 'setContext', 'showForm', 'register', 'unregister', 'setTheme', 'setLocale']) {
    expect(m).toMatch(new RegExp(`RCT_EXTERN_METHOD\\(${name}\\b`));
    expect(kt).toMatch(new RegExp(`@ReactMethod\\s+fun ${name}\\(`));
  }
  expect(m).toMatch(/RCT_EXPORT_VIEW_PROPERTY\(locale, NSString\)/);
  expect(fs.readFileSync('android/src/main/java/com/intunix/reactnative/IntunixFormViewManager.kt', 'utf8')).toMatch(/@ReactProp\(name = "locale"\)/);
});
