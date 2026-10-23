"use client";

import * as React from "react";

import { speechError, speechLocale } from "@/lib/speech";
import { useI18n } from "@/lib/i18n/client";

/**
 * Dictation, using the recogniser already in the browser.
 *
 * No key, no server, no audio leaving this code: `SpeechRecognition` is a
 * platform API, and the transcript arrives as text. The engine behind it is
 * the browser's own — in Chrome that means the audio goes to Google to be
 * recognised, which is worth knowing but is not something this app arranges
 * or can turn off.
 *
 * Only some browsers have it. Firefox has none, so `supported` is false there
 * and the button is not offered rather than offered and broken.
 */

/** The shape used here. The DOM lib does not ship these. */
type SpeechRecognitionAlternative = { transcript: string };
type SpeechRecognitionResult = {
  readonly isFinal: boolean;
  readonly length: number;
  [index: number]: SpeechRecognitionAlternative;
};
type SpeechResultEvent = {
  resultIndex: number;
  results: { length: number; [index: number]: SpeechRecognitionResult };
};
type SpeechErrorEvent = { error: string };
type Recogniser = {
  lang: string;
  continuous: boolean;
  interimResults: boolean;
  maxAlternatives: number;
  start: () => void;
  stop: () => void;
  abort: () => void;
  onresult: ((event: SpeechResultEvent) => void) | null;
  onerror: ((event: SpeechErrorEvent) => void) | null;
  onend: (() => void) | null;
};
type RecogniserClass = new () => Recogniser;

function recogniserClass(): RecogniserClass | null {
  if (typeof window === "undefined") return null;
  const w = window as unknown as {
    SpeechRecognition?: RecogniserClass;
    webkitSpeechRecognition?: RecogniserClass;
  };
  return w.SpeechRecognition ?? w.webkitSpeechRecognition ?? null;
}

/**
 * How long to keep listening after the last sound.
 *
 * `continuous` is on so a sentence with a pause in the middle of it is one
 * dictation rather than two, but that also means the recogniser will hold the
 * microphone open indefinitely. This closes it — someone who starts dictating
 * and is called away should not leave a live microphone behind.
 */
const SILENCE_MS = 6000;

/**
 * The level above which somebody is considered to still be talking.
 *
 * Well above a quiet room's noise floor and well below ordinary speech, which
 * the meter reads at around 0.4.
 */
const TALKING = 0.08;

/** How often sound is allowed to push the deadline back. */
const BUMP_EVERY_MS = 400;

/**
 * How long a stop request is given before it is taken by force.
 *
 * Long enough for a recogniser that is genuinely winding down to finish and
 * fire `onend` itself, short enough that a button press that did nothing is
 * not something you sit and wonder about.
 */
const STOP_GRACE_MS = 600;

/**
 * The pause before a finished recogniser is opened again.
 *
 * Not zero. A recogniser that has just fired `onend` is still letting go of
 * the microphone, and starting one in the same tick throws `InvalidStateError`
 * on every engine that does this. Long enough to be past that, short enough
 * that a breath between sentences is not a gap in the transcript.
 */
const REOPEN_MS = 220;

/**
 * A recogniser that ends sooner than this never really ran.
 *
 * The reopen has to be bounded or a broken engine loops forever, and counting
 * reopens is the wrong bound: someone thinking for five seconds between
 * sentences produces a run of perfectly ordinary short sessions, and a budget
 * would end their dictation for them. What is actually pathological is a
 * recogniser that ends the moment it starts, so that is what is counted.
 */
const BARREN_MS = 400;

/** How many of those in a row before giving up. */
const BARREN_LIMIT = 5;

export type SpeechInput = {
  /** False where the browser has no recogniser; the button is then hidden. */
  supported: boolean;
  listening: boolean;
  /** Words heard but not yet settled, for showing progress as you speak. */
  interim: string;
  /** A message key, or null. */
  error: string | null;
  /**
   * How loud it is right now, 0 to 1, in a ref rather than in state.
   *
   * A meter wants a new number every frame, and sixty renders a second of a
   * panel containing a chat thread to move some bars is not a trade worth
   * making. The meter reads this in its own animation frame and writes to the
   * DOM directly; React never sees it change.
   *
   * Stays at 0 when the level could not be measured — a second microphone
   * stream is a thing a browser is allowed to refuse, and dictation still
   * works when it does.
   */
  level: React.RefObject<number>;
  /** When listening began, for the elapsed count. Null when idle. */
  startedAt: number | null;
  start: () => void;
  stop: () => void;
  toggle: () => void;
};

/**
 * @param onText Called with each settled phrase, to append to whatever is
 *   being written. Interim words never go through it: they change as the
 *   engine reconsiders, and rewriting somebody's textbox under them is worse
 *   than showing the guess separately.
 */
export function useSpeechInput(onText: (text: string) => void): SpeechInput {
  const { locale } = useI18n();
  const [supported, setSupported] = React.useState(false);
  const [listening, setListening] = React.useState(false);
  const [interim, setInterim] = React.useState("");
  const [error, setError] = React.useState<string | null>(null);

  const [startedAt, setStartedAt] = React.useState<number | null>(null);

  const recogniser = React.useRef<Recogniser | null>(null);
  const silence = React.useRef<ReturnType<typeof setTimeout> | null>(null);
  /**
   * True from the moment the microphone is asked for until the answer comes
   * back. While it is set, nothing may tear the session down — see `onerror`.
   */
  const asking = React.useRef(false);
  /** Set when the recogniser failed while the microphone prompt was still up. */
  const engineFailed = React.useRef(false);
  /** One retry once permission arrives, so a refusal cannot loop. */
  const retried = React.useRef(false);
  /** True while the person still wants to be listened to. */
  const wanted = React.useRef(false);
  /** Consecutive recognisers that ended before they had run. */
  const barren = React.useRef(0);
  /** When the running recogniser was started, to tell those apart. */
  const engineStartedAt = React.useRef(0);
  /** The pending reopen, so stopping can cancel it. */
  const reopen = React.useRef<ReturnType<typeof setTimeout> | null>(null);
  /**
   * `launch` calling itself. A `useCallback` cannot name itself in its own
   * body, and the reopen below needs the current one, not the one from the
   * render that built the recogniser that just ended.
   */
  const relaunch = React.useRef<() => boolean>(() => false);

  // Fires if a stop request goes unanswered. See `stop`.
  const watchdog = React.useRef<ReturnType<typeof setTimeout> | null>(null);

  // The level meter's own plumbing. Separate from the recogniser: the engine
  // hears the words but tells us nothing about how loud they were, so the
  // microphone is opened a second time purely to measure it.
  const level = React.useRef(0);
  // Set while a session is running, so the level meter can push the silence
  // deadline back. Held in a ref because the meter loop outlives the render
  // that started it.
  const keepAlive = React.useRef<(() => void) | null>(null);
  const stream = React.useRef<MediaStream | null>(null);
  const audio = React.useRef<AudioContext | null>(null);
  const frame = React.useRef<number | null>(null);
  // Kept in a ref so the recogniser's handlers, which are attached once, always
  // call the current one rather than the one from the render that built them.
  const deliver = React.useRef(onText);
  deliver.current = onText;

  // Detection has to happen after mount: the server has no window, and
  // deciding on the server would render a button the browser then disagrees
  // with, which is a hydration mismatch.
  React.useEffect(() => setSupported(recogniserClass() !== null), []);

  const stopTimer = React.useCallback(() => {
    if (silence.current) clearTimeout(silence.current);
    silence.current = null;
  }, []);

  /**
   * Close the microphone the meter opened.
   *
   * Every track has to be stopped by hand. A `MediaStream` that is merely
   * dropped keeps the browser's recording indicator lit, which is alarming
   * and fair enough.
   */
  const stopMeter = React.useCallback(() => {
    if (frame.current !== null) cancelAnimationFrame(frame.current);
    frame.current = null;
    stream.current?.getTracks().forEach((track) => track.stop());
    stream.current = null;
    void audio.current?.close().catch(() => {});
    audio.current = null;
    level.current = 0;
  }, []);

  /**
   * Measure how loud the room is, sixty times a second.
   *
   * Takes a stream rather than opening one: the microphone is asked for once,
   * in the click, and both halves of this feature share the answer. Asking
   * twice meant two permission requests racing each other.
   *
   * Root mean square over the waveform, which is what a level meter measures —
   * peak would jump on a consonant and sit at zero through a vowel. The curve
   * is there because speech at a normal distance from a laptop microphone is
   * a small fraction of full scale, and a meter that reads 4% while somebody
   * talks does not tell them it is working, which is the entire job.
   */
  const listen = React.useCallback(
    (mic: MediaStream) => {
      try {
        stream.current = mic;

        const Ctx =
          window.AudioContext ??
          (window as unknown as { webkitAudioContext?: typeof AudioContext })
            .webkitAudioContext;
        if (!Ctx) return;

        const ctx = new Ctx();
        audio.current = ctx;
        // Safari hands back a suspended context; nothing is measured until it
        // is resumed, and the meter would sit flat through a whole sentence.
        if (ctx.state === "suspended") void ctx.resume();

        const analyser = ctx.createAnalyser();
        analyser.fftSize = 1024;
        analyser.smoothingTimeConstant = 0.6;
        ctx.createMediaStreamSource(mic).connect(analyser);

        const samples = new Uint8Array(analyser.fftSize);
        let lastBump = 0;
        const read = () => {
          analyser.getByteTimeDomainData(samples);
          let sum = 0;
          for (let i = 0; i < samples.length; i += 1) {
            const centred = (samples[i] - 128) / 128;
            sum += centred * centred;
          }
          const rms = Math.sqrt(sum / samples.length);
          const now = Math.min(1, Math.sqrt(rms) * 1.9);
          level.current = now;

          // Sound, not words, is what "still talking" means. The recogniser only
          // reports once it has settled a phrase, so a long or quietly-spoken
          // sentence could run past the deadline mid-breath and be cut off. The
          // meter knows there is a voice in the room a great deal sooner.
          if (now > TALKING && lastBump + BUMP_EVERY_MS < Date.now()) {
            lastBump = Date.now();
            keepAlive.current?.();
          }

          frame.current = requestAnimationFrame(read);
        };
        read();
      } catch {
        // No Web Audio, or it refused. Dictation carries on without a level.
        stopMeter();
      }
    },
    [stopMeter],
  );

  /**
   * Put everything back, from wherever.
   *
   * This used to live only in `onend`, and every way out of a session went
   * through it — which was fine right up until a browser did not fire it.
   * Safari does not, reliably, after a refused microphone: the recogniser was
   * finished, the panel still said "Listening…", the clock kept counting and
   * the stop button had nothing left to stop. There was no way out but a
   * reload.
   *
   * So nothing here waits to be told. It is idempotent, and it is the only
   * thing that clears the listening state.
   */
  const finish = React.useCallback(() => {
    wanted.current = false;
    asking.current = false;
    if (reopen.current) clearTimeout(reopen.current);
    reopen.current = null;
    engineFailed.current = false;
    keepAlive.current = null;
    stopTimer();
    if (watchdog.current) clearTimeout(watchdog.current);
    watchdog.current = null;
    stopMeter();
    recogniser.current = null;
    setListening(false);
    setStartedAt(null);
    setInterim("");
  }, [stopMeter, stopTimer]);

  const stop = React.useCallback(() => {
    // Set first: `onend` restarts the recogniser while this is true, and a
    // stop that raced the restart would be undone by it.
    wanted.current = false;
    const engine = recogniser.current;
    if (!engine) {
      // Nothing running, but the UI may still think there is. Clearing is
      // always safe, and is what makes a second press of a stuck button work.
      finish();
      return;
    }

    stopTimer();
    try {
      engine.stop();
    } catch {
      // Already dead. The watchdog below finishes the job.
    }

    // `stop()` is a request, not a guarantee: an engine that never truly
    // started ignores it and never fires `onend`. If the press has not taken
    // effect shortly, take it by force.
    if (watchdog.current) clearTimeout(watchdog.current);
    watchdog.current = setTimeout(() => {
      try {
        recogniser.current?.abort();
      } catch {
        // Nothing to abort.
      }
      finish();
    }, STOP_GRACE_MS);
  }, [finish, stopTimer]);

  /**
   * Build a recogniser and set it going.
   *
   * Separate from `start` because it is run twice on iOS: once inside the
   * click, and again if that attempt failed while the microphone prompt was
   * still on screen. Returns false if it would not start at all.
   */
  const launch = React.useCallback(() => {
    const Recognition = recogniserClass();
    if (!Recognition) return false;

    const engine = new Recognition();
    engine.lang = speechLocale(locale);
    engine.continuous = true;
    engine.interimResults = true;
    engine.maxAlternatives = 1;

    const bumpSilence = () => {
      if (silence.current) clearTimeout(silence.current);
      silence.current = setTimeout(() => {
        // The person has stopped talking, so they are done being listened to:
        // without this the restart below would open it straight back up.
        wanted.current = false;
        engine.stop();
      }, SILENCE_MS);
    };

    engine.onresult = (event) => {
      barren.current = 0;
      bumpSilence();
      let pending = "";
      for (let i = event.resultIndex; i < event.results.length; i += 1) {
        const result = event.results[i];
        const text = result[0]?.transcript ?? "";
        if (result.isFinal) {
          const settled = text.trim();
          if (settled) deliver.current(settled);
        } else {
          pending += text;
        }
      }
      setInterim(pending.trim());
    };

    engine.onerror = (event) => {
      const key = speechError(event.error);

      /**
       * Hold everything while the microphone prompt is still on screen.
       *
       * On iOS the recogniser does not raise that prompt — it goes through the
       * system speech service and fails immediately when it has no permission.
       * Tearing the session down here also cancelled the `getUserMedia` call
       * that *was* about to ask, so the prompt never appeared and the button
       * reported a blocked microphone nobody had been offered. The answer to
       * that question is seconds away; this waits for it.
       */
      if (asking.current) {
        engineFailed.current = true;
        return;
      }

      if (key) setError(key);
      if (event.error !== "no-speech") {
        // Before aborting, not after: `abort` fires `onend`, and `onend`
        // reopens the recogniser while this is still set. A failure would
        // otherwise restart itself straight into the same failure.
        wanted.current = false;
        try {
          engine.abort();
        } catch {
          // Already stopped.
        }
        finish();
      }
    };

    engine.onend = () => {
      /**
       * Some recognisers ignore `continuous` and stop at the first pause —
       * iOS among them, which is why dictation there caught one sentence and
       * then went deaf. While the person still wants to be listened to, open
       * it again rather than ending their sentence for them.
       *
       * A *new* recogniser, after a pause. Restarting the one that just ended,
       * in the tick it ended in, is the obvious thing to write and does not
       * work: the instance is spent and the microphone is still being let go
       * of, so `start()` throws and the session closed on the first pause
       * exactly as though none of this were here.
       */
      recogniser.current = null;
      keepAlive.current = null;
      // The old engine's silence timer still points at the old engine, and
      // firing would clear the wish to listen in the middle of a sentence.
      // The new one sets its own the moment it starts.
      stopTimer();

      barren.current =
        Date.now() - engineStartedAt.current < BARREN_MS ? barren.current + 1 : 0;

      if (!wanted.current || barren.current >= BARREN_LIMIT) {
        finish();
        return;
      }

      if (reopen.current) clearTimeout(reopen.current);
      reopen.current = setTimeout(() => {
        reopen.current = null;
        if (!wanted.current) {
          finish();
          return;
        }
        if (!relaunch.current()) finish();
      }, REOPEN_MS);
    };

    try {
      engine.start();
    } catch {
      // Chrome throws InvalidStateError if start() is called while a previous
      // session is still winding down.
      return false;
    }

    recogniser.current = engine;
    keepAlive.current = bumpSilence;
    engineStartedAt.current = Date.now();
    bumpSilence();
    return true;
  }, [finish, locale, stopTimer]);

  // Kept fresh so a reopen always runs the current closure.
  relaunch.current = launch;

  const start = React.useCallback(() => {
    if (recogniser.current || asking.current) return;

    setError(null);
    setInterim("");
    retried.current = false;
    barren.current = 0;
    engineFailed.current = false;
    wanted.current = true;

    /**
     * The microphone is asked for first, and synchronously, because this is
     * the call that raises the permission prompt — on iOS the recogniser never
     * does. It is not awaited before the recogniser starts: `start()` on a
     * recogniser wants the user gesture it was called from, and awaiting a
     * prompt spends that gesture.
     */
    asking.current = navigator.mediaDevices?.getUserMedia !== undefined;
    const answer = asking.current
      ? navigator.mediaDevices.getUserMedia({ audio: true })
      : null;

    const started = launch();
    if (!started && !answer) return;

    setListening(true);
    setStartedAt(Date.now());

    if (!answer) return;

    void answer.then(
      (mic) => {
        asking.current = false;
        if (!wanted.current) {
          mic.getTracks().forEach((track) => track.stop());
          return;
        }
        listen(mic);

        // Permission has just arrived. If the recogniser failed for the want
        // of it, that was the only thing wrong: try once more.
        if (engineFailed.current && !retried.current) {
          retried.current = true;
          engineFailed.current = false;
          setError(null);
          if (!launch()) finish();
        }
      },
      (refusal: unknown) => {
        asking.current = false;
        // A refusal is the answer to the whole question, not a note about the
        // meter: without a microphone there is nothing for either half to do.
        const denied =
          refusal instanceof DOMException &&
          (refusal.name === "NotAllowedError" ||
            refusal.name === "SecurityError");
        setError(denied ? "voice.blocked" : "voice.noMicrophone");
        // As above: clear the wish before aborting, or `onend` restarts a
        // recogniser that has just been refused a microphone.
        wanted.current = false;
        try {
          recogniser.current?.abort();
        } catch {
          // Nothing running.
        }
        finish();
      },
    );
  }, [finish, launch, listen]);

  const toggle = React.useCallback(() => {
    if (listening) stop();
    else start();
  }, [listening, start, stop]);

  // Leaving the page with the microphone open is not acceptable, and neither
  // is a recogniser still holding handlers into an unmounted component.
  React.useEffect(
    () => () => {
      if (silence.current) clearTimeout(silence.current);
      if (watchdog.current) clearTimeout(watchdog.current);
      if (reopen.current) clearTimeout(reopen.current);
      if (frame.current !== null) cancelAnimationFrame(frame.current);
      stream.current?.getTracks().forEach((track) => track.stop());
      void audio.current?.close().catch(() => {});
      recogniser.current?.abort();
      recogniser.current = null;
    },
    [],
  );

  return { supported, listening, interim, error, level, startedAt, start, stop, toggle };
}
