(
/** Image processing **/

// Take nrows of an image, skipping the first off rows
var getSegment = {|img, nrows, off|
    var seg;

    seg = Image.new(img.width, min(nrows, img.height - off));
    seg.pixels = img.pixels[off * img.width .. (off + nrows) * img.width];

    seg;
};

// Get the color at a given pixel (Image.getColor seems to be wrong)
var getColor = {|img, x, y|
    var pxVal = img.getPixel(x, y);

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

    // Scale values to be in [0, 1]
    vars[\disposition] = (vars[\disposition] + 1) / 2;
    vars[\energy] = vars[\energy];
    vars[\chaos] = vars[\chaos];

    vars;
};

/*** Music algorithms ***/

//
var updateRoot = Routine {|root = 0|
    inf.do {
        yield(root);

        root = root;
    };
};

//
var updateMode = Routine {|mode = \mixolydian|
    var trans;
    var oldDisp, newDisp, dDisp;

    trans = (
        major: (up: [\major], down: [\lydian, \mixolydian]),
        lydian: (up: [\major], down: [\mixolydian]),
        mixolydian: (up: [\major], down: [\dorian]),
        dorian: (up: [\mixolydian], down: [\minor]),
        minor: (up: [\dorian], down: [\phrygian, \locrian]),
        phrygian: (up: [\minor], down: [\locrian]),
        locrian: (up: [\minor], down: [\locrian])
    );
    oldDisp = 0.5;

    inf.do {
        newDisp = yield(mode);
        dDisp = newDisp - oldDisp;

        mode = case
        { abs(dDisp) <= 0.1 } { mode } // No change
        { abs(dDisp) > 0.1 } { trans[mode][\up].choose } // Go up
        { abs(dDisp) < 0.1 } { trans[mode][\down].choose }; // Go down

        oldDisp = newDisp;
    };
};

//
var updateTempo = Routine {|tempo = 60|
    var oldEnergy, newEnergy, dEnergy;
    var oldChaos, newChaos, dChaos;

    oldEnergy = 0.5;
    oldChaos = 0.5;

    inf.do {
        # newEnergy, newChaos = yield(tempo / 60);
        dEnergy = newEnergy - oldEnergy;
        dChaos = newChaos - oldChaos;

        tempo = tempo;

        oldEnergy = newEnergy;
        oldChaos = newChaos;
    };
};

//
var makeChords = {|durs, disp, chaos|
    var chords, chordTrans, chord2Type, type2Chord;

    chordTrans = (
        tonic: [[\tonic, 0.5], [\subdom, 0], [\dom, 0.5]],
        subdom: [[\tonic, 0], [\subdom, 0.1], [\dom, 0.9]],
        dom: [[\tonic, 0.9], [\subdom, 0], [\dom, 0.1]]
    );
    chord2Type = (
        0: \tonic, 2: \tonic, 5: \tonic,
        1: \subdom, 3: \subdom,
        4: \dom, 6: \dom
    );
    type2Chord = (
        tonic: [0, 2, 5],
        subdom: [1, 3],
        dom: [4, 6]
    );
    chords = List[0];

    (durs.size - 1).do {|idx|
        var type, wchords;

        type = chord2Type[chords[idx]];
        wchords = chordTrans[type].flop;
        wchords[1] = wchords[1] + chaos.rand;
        wchords[1] = wchords[1].normalizeSum;

        type = wchoose(wchords[0], wchords[1]);
        chords.add(type2Chord[type].choose);
    };

    chords;
};

//
var makeMelody = {|chords, disp, chaos|
    0 ! chords.size;
};

//
var getSection = Routine {|init|
    var sectionBars, root, mode;
    var amp, durs, sustain;
    var chords, notes;
    var oldDisp, newDisp, dDisp;
    var oldEnergy, newEnergy, dEnergy;
    var oldChaos, newChaos, dChaos;
    var lead, pad;
    var section;

    # sectionBars, root, mode = init;
    amp = 0.5 ! (4 * sectionBars);
    durs = 1 ! (4 * sectionBars);
    sustain = 1 ! (4 * sectionBars);

    oldDisp = 0.5;
    oldEnergy = 0.5;
    oldChaos = 0.5;

    chords = makeChords.value(durs, oldDisp, oldChaos);
    notes = makeMelody.value(chords, oldDisp, oldChaos);

    inf.do {
        chords.postln;
        notes.postln;
        lead = Pbind(
            \instrument, \default,
            \degree, Pseq(notes),
            \amp, Pseq(amp),
            \dur, Pseq(durs),
            \sustain, Pseq(sustain),
            \scale, Scale.at(mode),
            \ctranspose, root
        );
        pad = Pbind(
            \instrument, \default,
            \degree, Pseq(chords),
            \amp, Pseq(amp),
            \dur, Pseq(durs),
            \sustain, Pseq(sustain),
            \scale, Scale.at(mode),
            \ctranspose, root
        );
        section = Ppar([lead, pad, Padd(\degree, 2, pad), Padd(\degree, 4, pad)]);

        # newDisp, newEnergy, newChaos, root, mode = yield(section);
        dDisp = newDisp - oldDisp;
        dEnergy = newEnergy - oldEnergy;
        dChaos = newChaos - oldChaos;

        chords = makeChords.value(durs, newDisp, newChaos);
        notes = makeMelody.value(chords, newDisp, newChaos);

        oldDisp = newDisp;
        oldEnergy = newEnergy;
        oldChaos = newChaos;
    };
};

/*** Main loop ***/

//
var main = {
    var win, stopButton, nextButton;
    var imgs, img, seg, segSize, segOff, segMax;
    var root, mode, tempo;
    var play, clock;

    // Initialize input
    imgs = PathName.new(thisProcess.nowExecutingPath.dirname +/+ "imgs").files;
    imgs = [PathName.new(thisProcess.nowExecutingPath.dirname +/+ "imgs/trees.png")];
    img = Image.new(imgs.choose.fullPath);
    segSize = 40;
    segOff = 0;
    segMax = img.height;

    // Initialize display
    win = Window.new("Super Life 2 Melody", resizable: false).front;
    win.bounds = img.bounds.height_(img.bounds.height + 30);
    win.view.backgroundImage = img;

    stopButton = Button(win, Rect(0, img.bounds.height, win.bounds.width / 2, 30));
    stopButton.states = [["Stop", Color.black, Color.white]];
    stopButton.action = { play.stop; win.close; };

    nextButton = Button(win, stopButton.bounds.left_(win.bounds.width / 2));
    nextButton.states = [["Next", Color.black, Color.white]];
    nextButton.action = {
        img = Image.new(imgs.choose.fullPath);
        segMax = img.height;

        win.bounds = img.bounds.height_(img.bounds.height + 30);
        win.view.backgroundImage = img;
        stopButton.bounds = Rect(0, img.bounds.height, win.bounds.width / 2, 30);
        nextButton.bounds = stopButton.bounds.left_(win.bounds.width / 2);
    };

    // Song loop
    play = Routine {
        var inVars, section, sectionBars;

        // Initialize values
        inVars = (disposition: 0.5, energy: 0.5, chaos: 0.5);
        sectionBars = 4;

        // Initialize global music values
        updateRoot.next(0);
        updateMode.next(\mixolydian);
        updateTempo.next(60);

        // Initialize section
        getSection.next([sectionBars, 0, \mixolydian]);

        inf.do {
            // Update global music values
            root = updateRoot.next();
            mode = updateMode.next(inVars[\disposition]);
            tempo = updateTempo.next([inVars[\energy], inVars[\chaos]]);
            [root, mode, tempo].postln;
            inVars.postln;

            // Play next section
            clock.tempo = tempo;
            section = getSection.next([
                inVars[\disposition], inVars[\energy], inVars[\chaos],
                root, mode
            ]);
            section.play(clock);

            // Update input values
            {
                seg = getSegment.value(img, segSize, segOff);
                inVars = analyze.value(seg);
            }.defer;

            // Wait for section to end
            segOff = (segOff + 1) % segMax;
            clock.bars2beats(sectionBars).wait;
        };
    };

    // Start song
    clock = TempoClock.new;
    play.play(clock);
};

main.value();
);

x = Pbind(\degree, Pseq([0,1,2]));
y = Padd(\degree, 2, x);
z = Padd(\degree, 4, x);
Ppar([x, y, z]).play;

[1,2,3].wchoose([0.1, 0.8, 0.1]);
wchoose([1,2,3], [0.1, 0.7, 0.2]);
x = Pbind(\degree, Pseq([0, 7])).play;
x = (\a: 1, \b: 1, \c: 2);
x.invert;

{3.rand} ! 4

[1,2,3] + 4;
x = [[1,2,3], [0.1, 0.7, 0.2]];
wchoose(*x);

PathName.new(thisProcess.nowExecutingPath.dirname +/+ "imgs").files;
[PathName.new(thisProcess.nowExecutingPath.dirname +/+ "imgs/tree.png")]