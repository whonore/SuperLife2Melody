(
/** Image processing **/

// Take a random nrows x ncols section of img
var getSegment = {|img, nrows, ncols|
    var seg, pixels, startRow, startCol;

    nrows = min(nrows, img.height);
    ncols = min(ncols, img.width);

    startRow = (img.height - nrows + 1).rand;
    startCol = (img.width - ncols + 1).rand;

    // Take nrows, then just the first ncols of each row
    pixels = img.pixels[startRow * img.width .. ((startRow + nrows) * img.width) - 1];
    pixels = pixels.reshape(nrows, img.width);
    pixels = pixels.collect {|row| row[startCol .. (startCol + ncols) - 1]; };

    seg = Image.new(ncols, nrows);
    seg.pixels = Int32Array.newFrom(pixels.flat);

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
    vars[\disposition] = vars[\disposition].linlin(-1, 1, 0, 1);
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
var updateMode = Routine {|mode = \dorian|
    var trans, thresh;
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
    thresh = 0.05;
    oldDisp = 0.5;

    inf.do {
        newDisp = yield(mode);
        dDisp = newDisp - oldDisp;

        mode = case
        { dDisp > thresh } { trans[mode][\up].choose } // Go up
        { dDisp < thresh.neg } { trans[mode][\down].choose } // Go down
        { mode }; // No change

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
var getDurs = {|sectionBars, energy, chaos|
    var durs;
    var subDivs, energyLvl, subDiv;

    subDivs = [[1, 2], [4, 8]];
    subDiv = subDivs[energy.round].choose;
    //if ((subDiv > 2) && { 1.0.rand < chaos }, { subDiv = subDiv + [-1, 1].choose; });

    durs = (4 / subDiv) ! (sectionBars * subDiv);

    durs.sum.postln;
    durs;
};

//
var getAmps = {|durs, energy, chaos|
    var amp;

    amp = Array.fill(durs.size, {
        energy.linlin(0, 1, 0.3, 1) + ([-1, 1].choose * chaos.linlin(0, 1, 0, 0.1).rand);
    });

    amp;
};

//
var getChords = {|durs, disp, chaos|
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

    chaos = chaos.linlin(0, 1, 0, 0.2);

    (durs.size - 1).do {
        var type, wchords;

        type = chord2Type[chords.last];
        wchords = chordTrans[type].flop;
        wchords[1] = wchords[1] + chaos.rand;
        wchords[1] = wchords[1].normalizeSum;

        type = wchoose(wchords[0], wchords[1]);
        chords.add(type2Chord[type].choose);
    };

    chords;
};

//
var getMelody = {|chords, disp, chaos|
    var notes;
    var cons, diss, thresh;

    cons = [0, 2, 4];
    diss = [1, 3, 6];

    notes = chords.collect {|ch|
        var choices;

        choices = [ch, ch + 2, ch + 4];
        choices = choices ++ if (1.0.rand < chaos, { cons }, { diss });
        choices.asSet.choose;
    };

    notes;
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

    oldDisp = 0.5;
    oldEnergy = 0.5;
    oldChaos = 0.5;

    durs = getDurs.value(sectionBars, oldEnergy, oldChaos);
    amp = getAmps.value(durs, oldEnergy, oldChaos);
    sustain = 1 ! (4 * sectionBars);

    chords = getChords.value(durs, oldDisp, oldChaos);
    notes = getMelody.value(chords, oldDisp, oldChaos);

    inf.do {
        "".postln;
        "Amp: %\n".postf(amp);
        "Durs: %\n".postf(durs);
        "Chords: %\n".postf(chords);
        "Notes: %\n".postf(notes);

        lead = Pbind(
            \instrument, \default,
            \degree, Pseq(notes),
            \amp, Pseq(amp),
            \dur, Pseq(durs),
            // \sustain, Pseq(sustain),
            \scale, Scale.at(mode),
            \ctranspose, root,
            \octave, [5, 6].choose
        );
        pad = Pbind(
            \instrument, \default,
            \degree, Pseq(chords),
            \amp, Pseq(amp),
            \dur, Pseq(durs),
            // \sustain, Pseq(sustain),
            \scale, Scale.at(mode),
            \ctranspose, root,
            \octave, 4
        );
        section = Ppar([lead, pad, Padd(\degree, 2, pad), Padd(\degree, 4, pad)]);
        section = lead;

        # newDisp, newEnergy, newChaos, root, mode = yield(section);
        dDisp = newDisp - oldDisp;
        dEnergy = newEnergy - oldEnergy;
        dChaos = newChaos - oldChaos;

        durs = getDurs.value(sectionBars, newEnergy, newChaos);
        amp = getAmps.value(durs, newEnergy, newChaos);

        chords = getChords.value(durs, newDisp, newChaos);
        notes = getMelody.value(chords, newDisp, newChaos);

        oldDisp = newDisp;
        oldEnergy = newEnergy;
        oldChaos = newChaos;
    };
};

/*** Main loop ***/

//
var main = {
    var win, stopButton, nextButton;
    var imgs, img, seg, segSize;
    var root, mode, tempo;
    var play, clock;

    // Initialize input
    imgs = PathName.new(thisProcess.nowExecutingPath.dirname +/+ "imgs").files;
    //imgs = [PathName.new(thisProcess.nowExecutingPath.dirname +/+ "imgs/trees.png")];
    imgs = Pxrand(imgs, inf).asStream;
    img = Image.new(imgs.next.fullPath);
    segSize = 40;

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
        img = Image.new(imgs.next.fullPath);

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
        updateMode.next(\dorian);
        updateTempo.next(60);

        // Initialize section
        getSection.next([sectionBars, 0, \dorian]);

        inf.do {
            // Update global music values
            root = updateRoot.next();
            mode = updateMode.next(inVars[\disposition]);
            tempo = updateTempo.next([inVars[\energy], inVars[\chaos]]);

            "Root: %, Mode: %, Tempo: %\n".postf(root, mode, 60 * tempo);
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
                seg = getSegment.value(img, segSize, segSize);
                inVars = analyze.value(seg);
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