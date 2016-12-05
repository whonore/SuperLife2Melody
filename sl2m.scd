/*** Synth Defs ***/
(
// Sound recipes from:
// Mitchell Sigman (2011) Steal this Sound. Milwaukee, WI: Hal Leonard Books
// adapted for SuperCollider and elaborated by Nick Collins (http://www.sussex.ac.uk/Users/nc81/index.html)
// under GNU GPL 3 as per SuperCollider license

SynthDef(\winwoodlead, {
    |out = 0, freq = 440, amp = 0.1, gate = 1, cutoff = 8000, rq = 0.8,
    lfowidth = 0.01, lforate = 8, lagamount = 0.01, pan = 0.0|
    var pulse, filter, env, lfo;

    lfo = LFTri.kr(lforate, Rand(0, 2.0) ! 2);
    pulse = Mix(Pulse.ar(
        (freq.lag(lagamount)) * [1, 1.001] * (1.0 + (lfowidth * lfo)),
        [0.2, 0.19]
    )) * 0.5;
    filter =  RLPF.ar(pulse, cutoff, rq);

    // remove low end
    filter = BLowShelf.ar(filter, 351, 1.0, -9);
    env = EnvGen.ar(Env.adsr(0.01, 0.0, 0.9, 0.05), gate, doneAction: 2);

    Out.ar(out, Pan2.ar(filter * env * amp, pan));
}).add;

SynthDef(\everythingrhodes, {
    |out = 0, freq = 440, amp = 0.1, gate = 1, lforate = 4.85,
    lfowidth = 0.5, cutoff = 2000, rq = 0.5, pan = 0.0|
    var pulse, filter, env;

    pulse = Pulse.ar(freq * [1, 33.5.midiratio], [0.2, 0.1], [0.7, 0.3]);
    env = EnvGen.ar(Env.adsr(0.0, 1.0, 0.8, 3.0), gate, doneAction: 2);

    // keyboard tracking filter cutoff
    filter = BLowPass4.ar(pulse, (cutoff * (env.squared)) + 200 + freq, rq);

    Out.ar(out, Pan2.ar(Mix(filter) * env * amp, pan));
}).add;

SynthDef(\choruscompresseffect, {|out = 0, gate = 1|
    var source, chorus, env;

    source = In.ar(out, 2);
    env = Linen.kr(gate, 0.1, 1, 0.1, 2);

    chorus = Splay.ar(Array.fill(4, {
        var maxdelaytime = rrand(0.005, 0.02);

        DelayC.ar(
            source[0],
            maxdelaytime,
            LFNoise1.kr(Rand(0.1, 0.6), 0.25 * maxdelaytime, 0.75 * maxdelaytime)
        );
    }));

    chorus = Compander.ar(4 * (source + chorus), source, 0.4, 1, 4);

    XOut.ar(out, env, chorus);
}).add;
);

/*** Music ***/
(
/*** Image Processing ***/

// Take a random nrows x ncols section of img
var getSegment = {|img, nrows, ncols|
    var seg, pixels, startRow, startCol;

    // Keep within image size
    nrows = min(nrows, img.height);
    ncols = min(ncols, img.width);

    // Choose where to start
    startRow = (img.height - nrows + 1).rand;
    startCol = (img.width - ncols + 1).rand;

    // Take nrows, then just the first ncols of each row
    pixels = img.pixels[startRow * img.width .. ((startRow + nrows) * img.width) - 1];
    pixels = pixels.reshape(nrows, img.width);
    pixels = pixels.collect {|row| row[startCol .. (startCol + ncols) - 1]; };

    // Copy pixels
    seg = Image.new(ncols, nrows);
    seg.pixels = Int32Array.newFrom(pixels.flat);

    seg;
};

// Get the color at a given pixel (Image.getColor seems to be wrong)
var getColor = {|img, x, y|
    var pxVal = img.getPixel(x, y);

    // pxVal is #AARRGGBB
    Color.new255(
        (pxVal >> 16) & 0xFF,
        (pxVal >> 8) & 0xFF,
        (pxVal >> 0) & 0xFF,
        (pxVal >> 24) & 0xFF
    );
};

// Distill an image into a few variables
var analyze = {|img|
    var vars, colors;
    var reds, greens, blues;
    var diffs;

    vars = ();

    colors = Array.fill2D(img.height, img.width, {|r, c|
        getColor.value(img, c, r);
    });

    # reds, greens, blues = colors.flat.collect {|col| col.asArray;}.flop;

    // Compare amount of red to blue (in range [-1, 1])
    vars[\disposition] = ((reds.sum - blues.sum) / (reds.sum + blues.sum + greens.sum));
    if (vars[\disposition].isNaN, { vars[\disposition] = 0; });

    // Take the average brightness (in range [0, 1])
    // Brightness of (r,g,b) is mean of min(r,g,b) and max(r,g,b)
    vars[\energy] = [reds, greens, blues].flop.collect {|col|
        [col.minItem, col.maxItem].mean;
    }.mean;

    // Take the average difference between vertically and horizontally
    // adjacent pixels (in range [0, 1])
    diffs = List[];
    colors.doAdjacentPairs {|row1, row2| // vertically adjacent
        [row1, row2].flop.do {|ps|
            var diffCol;

            diffCol = ps[0].symmetricDifference(ps[1]);
            diffs.add((diffCol.asArray[0..2] ** 2).sum);
        };
    };
    colors.flop.doAdjacentPairs {|row1, row2| // horizontally adjacent
        [row1, row2].flop.do {|ps|
            var diffCol;

            diffCol = ps[0].symmetricDifference(ps[1]);
            diffs.add((diffCol.asArray[0..2] ** 2).sum);
        };
    };
    vars[\chaos] = diffs.mean;

    vars;
};

/*** Helper Functions ***/

// Align two lists of durations by time
var alignTime = {|durs1, durs2|
    var aligned, parSum1, parSum2;

    // Create lists of the start times of each note
    parSum1 = durs1.integrate - durs1;
    parSum2 = durs2.integrate - durs2;

    // For each time in durs1, find the index of the corresponding time
    // in durs2 or the next largest time
    aligned = List[];
    parSum1.do {|time|
        aligned.add(parSum2.indexOfGreaterThan(time) ? parSum2.size);
    };

    // Return the time-aligned mapping of indices
    aligned - 1;
};

/*** Music Algorithms ***/

// Choose the new root by moving up or down 1 or 2 steps
var updateRoot = Routine {|initVars|
    var root, thresh;
    var oldVars, newVars, dVars;

    oldVars = initVars;
    thresh = 0.1;

    // Initialize root
    root = 0;

    inf.do {
        var choices;

        newVars = yield(root);
        dVars = merge(newVars, oldVars, {|x, y| x - y; });

        // Up or down 1 or 2 steps
        choices = root + [-2, -1, 1, 2];

        // Clip within +/- 3 of original root
        choices = choices.clip2(3);

        // Update root
        root = if (1.0.rand <= thresh, { choices.asSet.choose; }, { root; });

        oldVars = newVars;
    };
};

// Choose the new mode using a NFA
var updateMode = Routine {|initVars|
    var mode, trans, thresh;
    var oldVars, newVars, dVars;

    trans = (
        major: (up: [\major], down: [\lydian, \mixolydian]),
        lydian: (up: [\major], down: [\mixolydian]),
        mixolydian: (up: [\major], down: [\dorian]),
        dorian: (up: [\mixolydian], down: [\minor]),
        minor: (up: [\dorian], down: [\phrygian, \locrian]),
        phrygian: (up: [\minor], down: [\locrian]),
        locrian: (up: [\minor], down: [\locrian])
    );
    thresh = 0.05;
    oldVars = initVars;

    // Initialize mode
    mode = [
        \locrian, \phrygian, \minor, \dorian, \mixolydian, \lydian, \major
    ][oldVars[\disposition].linlin(0, 1, 0, 6).round];

    inf.do {
        newVars = yield(mode);
        dVars = merge(newVars, oldVars, {|x, y| x - y; });

        // Update mode
        mode = case
        { dVars[\disposition] > thresh } { trans[mode][\up].choose } // Go up
        { dVars[\disposition] < thresh.neg } { trans[mode][\down].choose } // Go down
        { mode }; // No change

        oldVars = newVars;
    };
};

// Choose the new tempo as a function of energy
var updateTempo = Routine {|initVars|
    var tempo, minTempo, maxTempo, tempoBound;
    var oldVars, newVars, dVars;

    oldVars = initVars;

    // Initialize tempo
    minTempo = 30;
    maxTempo = 120;
    tempoBound = 10;
    tempo = if (oldVars[\energy] <= 0.5,
        { oldVars[\energy].lincurve(0, 0.5, minTempo, [minTempo, maxTempo].mean, 2); },
        { oldVars[\energy].lincurve(0.5, 1, [minTempo, maxTempo].mean, maxTempo, -2); }
    );

    inf.do {
        newVars = yield(tempo / 60);
        dVars = merge(newVars, oldVars, {|x, y| x - y; });

        // Update tempo
        tempo = if (newVars[\energy] <= 0.5,
            { newVars[\energy].lincurve(0, 0.5, minTempo, [minTempo, maxTempo].mean, 2); },
            { newVars[\energy].lincurve(0.5, 1, [minTempo, maxTempo].mean, maxTempo, -2); }
        ).clip(tempo - tempoBound, tempo + tempoBound);

        oldVars = newVars;
    };
};

// Choose the duration for the pad instrument based on energy
var getPadDurs = {|inVars, sectionBars|
    var durs;
    var subDivs, subDiv;

    // Choose based on energy
    subDivs = [[2], [4, 8]];
    subDiv = subDivs[inVars[\energy].round].choose;

    // Have a chance of changing to a non-binary division
    if (1.0.rand < inVars[\chaos], { subDiv = subDiv + (-1 .. 1).choose; });

    durs = (4 / subDiv) ! (sectionBars * subDiv);

    durs;
};

// Choose the durations for the lead instruments by transforming the pad durations
var getLeadDurs = {|inVars, padDurs|
    var durs;
    var choices, choice;

    choices = (
        half: {|dur| dur[0, 2 ..] * 2; }, // Only works assuming padDurs is even in length
        same: {|dur| dur; },
        double: {|dur| dur.stutter(2) / 2; },
        triple: {|dur| dur.stutter(3) / 3; },
        quad: {|dur| dur.stutter(4) / 4; }
    );

    // Transform padDurs
    choice = [\half, \same, \double, \triple, \quad][inVars[\energy].linlin(0, 1, 0, 4).round];
    durs = choices[choice].value(padDurs);

    // durs +/- chaos

    durs = durs.normalizeSum * padDurs.sum;

    durs;
};

// Choose the amplitudes as a function of energy
var getAmps = {|inVars, durs|
    var amp;

    amp = Array.fill(durs.size, {
        inVars[\energy].linlin(0, 1, 0.3, 0.7)
        + ([-1, 1].choose * inVars[\chaos].linlin(0, 1, 0, 0.1).rand);
    });

    amp;
};

// Choose the chords by functional type
var getChords = {|inVars, durs|
    var chords, type;
    var chordTrans, chord2Type, type2Chord;

    chordTrans = (
        tonic: [[\tonic, 0.5], [\subdom, 0], [\dom, 0.5]],
        subdom: [[\tonic, 0], [\subdom, 0.1], [\dom, 0.9]],
        dom: [[\tonic, 0.9], [\subdom, 0], [\dom, 0.1]]
    );
    type2Chord = (
        tonic: [0, 2, 5],
        subdom: [1, 3],
        dom: [4, 6]
    );

    // Start at tonic
    chords = Array.new(durs.size);
    chords.add(0);
    type = \tonic;

    (durs.size - 1).do {
        var wchords;

        // Get transition probabilities
        wchords = chordTrans[type].flop;

        // Add variation
        wchords[1] = wchords[1] + inVars[\chaos].linlin(0, 1, 0, 0.2).rand;
        wchords[1] = wchords[1].normalizeSum;

        // Choose next chord type and chord
        type = wchoose(wchords[0], wchords[1]);
        chords.add(type2Chord[type].choose);
    };

    chords;
};

// Choose the lead notes from among the chord tones and other intervals
var getMelody = {|inVars, leadDurs, padDurs, chords|
    var notes, aligned;
    var cons, diss, wcons, wdiss, thresh;

    // Align the lead and pad durations
    aligned = alignTime.value(leadDurs, padDurs);

    // Consonant and dissonant intervals
    cons = [0, 2, 4];
    diss = [1, 3, 6];

    // Corresponding weights
    wcons = 2 ! cons.size;
    wdiss = inVars[\chaos] ! diss.size;

    notes = Array.fill(leadDurs.size, {|idx|
        var chord, choices, wchoices;

        // Look at the current chord
        chord = chords[aligned[idx]];

        // Choose from the chord tones, consonant intervals, and dissonant intervals
        choices = [chord, chord + 2, chord + 4, cons, diss].flat;
        wchoices = [1 ! 3, wcons, wdiss].flat;
        choices.wchoose(wchoices.normalizeSum(1));
    });

    notes;
};

// Create a 4-bar section
var getSection = Routine {|init|
    var sectionBars, root, mode;
    var leadAmps, padAmps, leadDurs, padDurs;
    var chords, notes;
    var oldVars, newVars, dVars;
    var lead, pad;
    var section;

    # oldVars, sectionBars, root, mode = init;

    // Initialize values
    padDurs = getPadDurs.value(oldVars, sectionBars);
    padAmps = getAmps.value(oldVars, padDurs);
    leadDurs = getLeadDurs.value(oldVars, padDurs);
    leadAmps = getAmps.value(oldVars, leadDurs);

    chords = getChords.value(oldVars, padDurs);
    notes = getMelody.value(oldVars, leadDurs, padDurs, chords);

    inf.do {
        "Lead Amps: %\n".postf(leadAmps);
        "Pad Amps: %\n".postf(padAmps);
        "Lead Durs: %\n".postf(leadDurs);
        "Pad Durs: %\n".postf(padDurs);
        "Chords: %\n".postf(chords);
        "Notes: %\n".postf(notes);

        // Create instruments
        lead = Pmono(
            \winwoodlead,
            \degree, Pseq(notes),
            \amp, Pseq(leadAmps),
            \dur, Pseq(leadDurs),
            \scale, Scale.at(mode),
            \ctranspose, root,
            \octave, [5, 6].choose,
            \lagamount, 0.1,
            \lfowidth, 0.005,
            \cutoff, 2000
        );
        pad = Pfx(
            Pbind(
                \instrument, \everythingrhodes,
                \degree, Pseq([chords, chords + 2, chords + 4].flop),
                \amp, Pseq(padAmps * 0.1),
                \dur, Pseq(padDurs),
                \scale, Scale.at(mode),
                \ctranspose, root,
                \octave, 4,
                \cutoff, 1000
            ),
            \choruscompresseffect
        );
        section = Ppar([lead, pad]);

        # newVars, sectionBars, root, mode = yield(section);
        dVars = merge(newVars, oldVars, {|x, y| x - y; });

        // Update values
        padDurs = getPadDurs.value(newVars, sectionBars);
        padAmps = getAmps.value(newVars, padDurs);
        leadDurs = getLeadDurs.value(newVars, padDurs);
        leadAmps = getAmps.value(newVars, leadDurs);

        chords = getChords.value(newVars, padDurs);
        notes = getMelody.value(newVars, leadDurs, padDurs, chords);

        oldVars = newVars;
    };
};

/*** Main loop ***/

// Infinitely analyze the input and generate music
var main = {
    var win, segWin, stopButton, nextButton;
    var imgs, img, seg, segSize;
    var root, mode, tempo;
    var play, clock;

    // Initialize input
    imgs = PathName.new(thisProcess.nowExecutingPath.dirname +/+ "imgs").files;
    imgs = Pxrand(imgs, inf).asStream;
    img = Image.new(imgs.next.fullPath);
    segSize = 40;

    // Initialize display
    win = Window.new("Super Life 2 Melody", resizable: false).front;
    win.bounds = img.bounds.height_(img.bounds.height + 30);
    win.view.backgroundImage = img;

    stopButton = Button(win, Rect(0, img.bounds.height, win.bounds.width / 2, 30));
    stopButton.states = [["Stop", Color.black, Color.white]];
    stopButton.action = { play.stop; win.close; segWin.close; };

    nextButton = Button(win, stopButton.bounds.left_(win.bounds.width / 2));
    nextButton.states = [["Next", Color.black, Color.white]];
    nextButton.action = {
        img = Image.new(imgs.next.fullPath);

        win.bounds = img.bounds.height_(img.bounds.height + 30);
        win.view.backgroundImage = img;
        stopButton.bounds = Rect(0, img.bounds.height, win.bounds.width / 2, 30);
        nextButton.bounds = stopButton.bounds.left_(win.bounds.width / 2);
    };

    // Song loop
    play = Routine {
        var inited, section, sectionBars;
        var inVars, minVars, maxVars;

        // Initialize values
        inited = Condition.new(false);
        {
            // Find bounds for vars
            minVars = ();
            maxVars = ();
            10.do {
                seg = getSegment.value(img, segSize, segSize);
                inVars = analyze.value(seg);
                minVars = merge(inVars, minVars, {|x, y| min(x, y); });
                maxVars = merge(inVars, maxVars, {|x, y| max(x, y); });
            };

            // Scale vars
            inVars = inVars.collect {|v, k|
                v.linlin(minVars[k], maxVars[k], 0, 1);
            };

            segWin = seg.plot("Current Segment");

            inited.test = true;
            inited.signal;
        }.defer;
        sectionBars = 4;

        // Wait for values to be initialized
        inited.wait;

        inf.do {
            // Update global music values
            root = updateRoot.next(inVars);
            mode = updateMode.next(inVars);
            tempo = updateTempo.next(inVars);

            "\n%\nRoot: %, Mode: %, Tempo: %\n".postf(inVars, root, mode, 60 * tempo);

            // Play next section
            clock.tempo = tempo;
            section = getSection.next([inVars, sectionBars, root, mode]);
            section.play(clock);

            // Update input values
            {
                segWin.close;
                seg = getSegment.value(img, segSize, segSize);
                inVars = analyze.value(seg);

                // Rescale inVars
                minVars = merge(inVars, minVars, {|x, y| min(x, y); });
                maxVars = merge(inVars, maxVars, {|x, y| max(x, y); });
                inVars = inVars.collect {|v, k|
                    v.linlin(minVars[k], maxVars[k], 0, 1);
                };

                segWin = seg.plot("Current Segment");
            }.defer;

            // Wait for section to end
            clock.bars2beats(sectionBars).wait;
        };
    };

    // Start song
    clock = TempoClock.new;
    play.play(clock);
};

main.value();
);