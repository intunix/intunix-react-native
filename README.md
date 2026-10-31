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
npm install github:intunix/intunix-react-native
cd ios && pod install
```

- **iOS:** the iOS SDK comes from Swift Package Manager; the podspec pulls it in with React
  Native's `spm_dependency` (0.75+). Nothing else to do.
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

Options, triggers and what is sent are the same as the native SDKs — see their READMEs.
