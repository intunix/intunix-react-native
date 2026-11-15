# Intunix for React Native

Show [Intunix](https://intunix.com) feedback forms in React Native apps. This package wraps the
native Intunix SDKs ([Android](https://github.com/intunix/intunix-android),
[iOS](https://github.com/intunix/intunix-ios)), so forms look and behave exactly as on the web
and in native apps: the same questions, pages, conditional questions, icon styles, cadence,
targeting and review requests.

React Native 0.76+ (old or new architecture) · Android 7.0+ · iOS 15+ · not Expo Go
(use a development build)

## Install

```bash
npm install @intunix/react-native
cd ios && pod install
```

- **iOS:** the pod includes the Intunix iOS SDK sources (pinned in `ios/IntunixSDK/VERSION`).
  Nothing else to do.
- **Android:** the SDK comes from JitPack; the package adds that repository for you. If your
  `android/settings.gradle` sets `repositoriesMode` to `FAIL_ON_PROJECT_REPOS`, add
  `maven { url "https://jitpack.io" }` to its repositories.

## Use

```ts
import { Intunix, IntunixForm } from '@intunix/react-native';

Intunix.initialize('ck_your_client_key', { registerAll: true });

Intunix.identify('user-42', { plan: 'pro' });    // on every login
Intunix.reset();                                 // on logout
Intunix.track('checkout_completed', { total: 49 });
Intunix.screen('Checkout');                      // drives "App screen" triggers
Intunix.setContext({ store: 'dhaka-1' });        // sent with responses; null clears
Intunix.showForm('nps-q4');                      // id or slug; respects cadence
```

Modal forms show as a centered dialog, popup and banner forms as a bottom sheet. For an inline
form, put the component in your layout; it sizes itself to the form:

```tsx
<IntunixForm form="post-order" onFinished={() => setDone(true)} />
```

### Dark mode

Forms follow your app's light/dark setting, including `Appearance.setColorScheme`.
Each form can also be locked to light or dark in the console. To override from code
(code wins over the console):

```ts
Intunix.initialize('ck_your_client_key', { theme: 'auto' }); // 'auto' | 'light' | 'dark'
Intunix.setTheme('dark');                                    // any time
<IntunixForm form="post-order" theme="light" />
```

### Languages

A form can be written in several languages (set up in the console). Which one a respondent
sees is chosen automatically, in this order:

1. the language the respondent picked in the form's switcher (remembered on the device);
2. your app's language: the `locale` option, `setLocale()`, or the per-form `locale`;
3. the device's language list;
4. the form's own default language.

A form with two or more languages shows a language switcher; switching keeps the answers.
Right-to-left languages (Arabic, Persian, Hebrew, Urdu) lay out right to left natively.
Responses carry the `language` they were answered in.

```ts
Intunix.initialize('ck_your_client_key', { locale: 'bn' });  // the app's language
Intunix.setLocale('pt-BR');                                  // any time; replaces the remembered choice
<IntunixForm form="nps-q3" locale="ar" />                    // this form only
```

`setLocale()` replaces the remembered choice, so use it when the user picks a language in
your own settings screen. A form reads its locale when it loads; a form already on screen
keeps its language until it is shown again. `reset()` (on logout) forgets the remembered
language. Limit: a follow-up question asked before a language switch stays in the language
it was asked in.

### Conversational forms

Forms can be AI-enhanced (follow-up questions after an answer) or run as a chat. Both are
set in the console, so there is nothing to code and no change to existing `showForm` or
inline form calls. The assistant's name is set in the console too (default "Nia"). If the AI
is unreachable (offline, or a server error) the form carries on with its own questions. A
conversation resumes after an app restart until it ends.

Options, triggers and what is sent are the same as the native SDKs — see their READMEs.
