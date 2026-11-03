import { Intunix } from '../src';
import { calls } from './react-native-mock';

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
