import { useState, type ComponentType } from 'react';
import { NativeModules, Platform, requireNativeComponent, type ViewProps, type NativeSyntheticEvent } from 'react-native';

/** Options for {@link Intunix.initialize}. Names follow the web and native SDKs. */
export interface IntunixOptions {
  /** API origin. Leave as is unless Intunix gave you another host. */
  apiHost?: string;
  /** Forms (ids or slugs) whose triggers should be live. Auto-activate forms are live anyway. */
  register?: string[];
  /** Load the whole SDK-enabled catalog instead of only `register`. */
  registerAll?: boolean;
  flushIntervalMs?: number;
  maxQueueSize?: number;
  /** Wait before a screen-triggered form shows. */
  screenTriggerDelayMs?: number;
  /** Keep tracked events on the device (they still fire event triggers). */
  disableEventApi?: boolean;
  /** Native SDK logs (Logcat / Xcode console). */
  debug?: boolean;
  /** Dark mode override. 'auto' (default) = the form's console lock, else follow the app. */
  theme?: IntunixTheme;
  /** Developer default language (e.g. 'bn', 'pt-BR'); loses to the respondent's own earlier choice. Read when a form loads. */
  locale?: string;
}

/** Light or dark forms. 'auto' follows the console lock, else the app's light/dark setting. */
export type IntunixTheme = 'auto' | 'light' | 'dark';

export type JsonValue = string | number | boolean | null | JsonValue[] | { [k: string]: JsonValue };
export type Properties = Record<string, JsonValue>;

const LINKING_ERROR =
  `@intunix/react-native is not linked. ${Platform.select({ ios: "Run 'pod install' in ios/. ", default: '' })}` +
  'Rebuild the app after installing the package (Expo Go is not supported; use a development build).';

const Native: {
  initialize(apiKey: string, options: IntunixOptions): void;
  identify(userId: string, traits: Properties): void;
  reset(): void;
  track(event: string, properties: Properties): void;
  screen(name: string): void;
  setContext(context: Properties | null): void;
  showForm(form: string, context: Properties | null): void;
  register(form: string): void;
  unregister(form: string): void;
  setTheme(theme: IntunixTheme): void;
  setLocale(code: string): void;
} = NativeModules.Intunix ?? new Proxy({}, { get() { throw new Error(LINKING_ERROR); } });

/** Intunix feedback forms. Call `initialize` once, at app start. */
export const Intunix = {
  version: '1.7.1',
  initialize: (apiKey: string, options: IntunixOptions = {}) => Native.initialize(apiKey, options),
  /** Identify the signed-in user. Call on every login. */
  identify: (userId: string, traits: Properties = {}) => Native.identify(userId, traits),
  /** Call on logout: forgets the user, rotates the anonymous id and ends the session. */
  reset: () => Native.reset(),
  track: (event: string, properties: Properties = {}) => Native.track(event, properties),
  /** Tell Intunix which screen is showing. Drives "App screen" triggers and screen targeting. */
  screen: (name: string) => Native.screen(name),
  /** Merge values into the session context sent with responses; null clears it. */
  setContext: (context: Properties | null) => Native.setContext(context),
  clearContext: () => Native.setContext(null),
  /** Show a form now (still subject to its cadence and targeting). Accepts the form id or slug. */
  showForm: (idOrSlug: string, context?: Properties) => Native.showForm(idOrSlug, context ?? null),
  /** Make a form's triggers live. */
  register: (idOrSlug: string) => Native.register(idOrSlug),
  unregister: (idOrSlug: string) => Native.unregister(idOrSlug),
  /** Force light or dark forms, or 'auto'. Open forms switch at once; beats the console lock. */
  setTheme: (theme: IntunixTheme) => Native.setTheme(theme),
  /**
   * The app's language changed: forms shown from now on use `code` (multi-language forms only),
   * replacing the respondent's remembered choice. Already-loaded forms are not re-localized.
   */
  setLocale: (code: string) => Native.setLocale(code),
};

interface NativeFormProps extends ViewProps {
  form: string;
  formContext?: Properties | null;
  theme?: IntunixTheme | null;
  locale?: string | null;
  onHeightChange?: (e: NativeSyntheticEvent<{ height: number }>) => void;
  onFinished?: (e: NativeSyntheticEvent<Record<string, never>>) => void;
}

let NativeForm: ComponentType<NativeFormProps> | null = null;
const nativeForm = () => (NativeForm ??= requireNativeComponent<NativeFormProps>('IntunixFormView'));

export interface IntunixFormProps extends ViewProps {
  /** Form id or slug. */
  form: string;
  /** Values sent with the response, on top of `Intunix.setContext`. */
  context?: Properties;
  /** Called once the visitor submits or closes the form. */
  onFinished?: () => void;
  /** Light/dark for this form; unset = `Intunix.setTheme`, the console lock, then the app. */
  theme?: IntunixTheme;
  /** Language for this form; unset = `Intunix.setLocale`/`locale` option, then the respondent's choice. Read when the form loads; changing it later does not re-localize it. */
  locale?: string;
}

/**
 * A form placed in your own layout (the web SDK's inline form). Takes the form's height,
 * draws nothing until it loads, and collapses once the visitor is done.
 */
export function IntunixForm({ form, context, onFinished, theme, locale, style, ...rest }: IntunixFormProps) {
  // A native view needs a non-zero size before it can measure its content.
  const [height, setHeight] = useState(1);
  const View = nativeForm();
  return (
    <View
      {...rest}
      form={form}
      formContext={context ?? null}
      theme={theme ?? null}
      locale={locale ?? null}
      style={[style, { height }]}
      onHeightChange={(e: NativeSyntheticEvent<{ height: number }>) => setHeight(Math.max(1, e.nativeEvent.height))}
      onFinished={() => onFinished?.()}
    />
  );
}

export default Intunix;
