//
//  DevelopRevealTests.swift
//  HeicSwapTests
//
//  The pure visual recipe behind the "developing" reveal (task 5.3): a developed thumbnail is
//  always full color; an undeveloped one sweeps brightness/saturation up — unless Reduce Motion is
//  on, in which case it must be a pure opacity crossfade instead (AC2). The animated cell itself is
//  verified manually; these lock the branch behaviour the cell relies on.
//

import Testing
@testable import HeicSwap

struct DevelopRevealTests {

    @Test("A developed thumbnail is full color regardless of Reduce Motion", arguments: [false, true])
    func developedIsFullColor(reduceMotion: Bool) {
        let style = DevelopReveal.style(isDeveloped: true, reduceMotion: reduceMotion)
        #expect(style == DevelopReveal.developed)
    }

    @Test("AC2: Reduce Motion replaces the sweep with an opacity-only crossfade")
    func reduceMotionIsCrossfadeOnly() {
        let undeveloped = DevelopReveal.style(isDeveloped: false, reduceMotion: true)
        // Only opacity moves — brightness and saturation hold at their developed values, so there
        // is no brightness/saturation sweep, just a crossfade.
        #expect(undeveloped.brightness == DevelopReveal.developed.brightness)
        #expect(undeveloped.saturation == DevelopReveal.developed.saturation)
        #expect(undeveloped.opacity < DevelopReveal.developed.opacity)
    }

    @Test("With motion allowed, undeveloped sweeps brightness/saturation but not opacity")
    func motionSweepsBrightnessNotOpacity() {
        let undeveloped = DevelopReveal.style(isDeveloped: false, reduceMotion: false)
        // The develop sweep darkens and desaturates while opacity stays at full — no fade.
        #expect(undeveloped.brightness < DevelopReveal.developed.brightness)
        #expect(undeveloped.saturation < DevelopReveal.developed.saturation)
        #expect(undeveloped.opacity == DevelopReveal.developed.opacity)
    }
}
