// Generated from the pinned OSGB expert reference by scripts/isg/nova_tokens.mjs.
// No other-role themes, backend rules or runtime activation. Do not edit by hand.
package com.riskdetectedan.core.designsystem.isg

data class NovaRGBA(val red: Int, val green: Int, val blue: Int, val alpha: Double)

enum class NovaColorToken {
    canvas, canvasSheet, surface, surfacePressed, surfaceMuted, glass, glassBorder, text, textSecondary, textTertiary, textMuted, textSubtle, textPlaceholder, onDark, hairline, border, borderStrong, borderMuted, inverse, onInverse, scrim, accent, accentInk, accentSoft, onAccent, statusSuccessBg, statusSuccessInk, statusSuccessDot, statusWarningBg, statusWarningInk, statusWarningDot, statusDangerBg, statusDangerInk, statusDangerDot, statusInfoBg, statusInfoInk, statusInfoDot, statusNeutralBg, statusNeutralInk, statusNeutralDot;

    fun rgba(dark: Boolean): NovaRGBA = when (this) {
        canvas -> if (dark) NovaRGBA(17, 17, 20, 1.0) else NovaRGBA(240, 240, 240, 1.0)
        canvasSheet -> if (dark) NovaRGBA(23, 23, 27, 1.0) else NovaRGBA(247, 247, 248, 1.0)
        surface -> if (dark) NovaRGBA(28, 28, 33, 1.0) else NovaRGBA(255, 255, 255, 1.0)
        surfacePressed -> if (dark) NovaRGBA(35, 35, 41, 1.0) else NovaRGBA(250, 250, 250, 1.0)
        surfaceMuted -> if (dark) NovaRGBA(38, 38, 43, 1.0) else NovaRGBA(244, 244, 245, 1.0)
        glass -> if (dark) NovaRGBA(28, 28, 33, 0.62) else NovaRGBA(255, 255, 255, 0.62)
        glassBorder -> if (dark) NovaRGBA(255, 255, 255, 0.09) else NovaRGBA(255, 255, 255, 0.7)
        text -> if (dark) NovaRGBA(245, 245, 247, 1.0) else NovaRGBA(17, 17, 17, 1.0)
        textSecondary -> if (dark) NovaRGBA(201, 201, 208, 1.0) else NovaRGBA(75, 75, 82, 1.0)
        textTertiary -> if (dark) NovaRGBA(168, 168, 174, 1.0) else NovaRGBA(107, 107, 114, 1.0)
        textMuted -> if (dark) NovaRGBA(139, 139, 143, 1.0) else NovaRGBA(139, 139, 143, 1.0)
        textSubtle -> if (dark) NovaRGBA(111, 111, 119, 1.0) else NovaRGBA(168, 168, 174, 1.0)
        textPlaceholder -> if (dark) NovaRGBA(124, 124, 132, 1.0) else NovaRGBA(154, 154, 159, 1.0)
        onDark -> if (dark) NovaRGBA(255, 255, 255, 1.0) else NovaRGBA(255, 255, 255, 1.0)
        hairline -> if (dark) NovaRGBA(255, 255, 255, 0.08) else NovaRGBA(17, 17, 17, 0.07)
        border -> if (dark) NovaRGBA(255, 255, 255, 0.12) else NovaRGBA(17, 17, 17, 0.1)
        borderStrong -> if (dark) NovaRGBA(58, 58, 66, 1.0) else NovaRGBA(213, 213, 218, 1.0)
        borderMuted -> if (dark) NovaRGBA(43, 43, 49, 1.0) else NovaRGBA(236, 236, 239, 1.0)
        inverse -> if (dark) NovaRGBA(245, 245, 247, 1.0) else NovaRGBA(17, 17, 17, 1.0)
        onInverse -> if (dark) NovaRGBA(17, 17, 20, 1.0) else NovaRGBA(255, 255, 255, 1.0)
        scrim -> if (dark) NovaRGBA(0, 0, 0, 0.55) else NovaRGBA(15, 15, 17, 0.38)
        accent -> if (dark) NovaRGBA(46, 210, 86, 1.0) else NovaRGBA(46, 210, 86, 1.0)
        accentInk -> if (dark) NovaRGBA(15, 122, 52, 1.0) else NovaRGBA(15, 122, 52, 1.0)
        accentSoft -> if (dark) NovaRGBA(21, 58, 36, 1.0) else NovaRGBA(234, 251, 239, 1.0)
        onAccent -> if (dark) NovaRGBA(255, 255, 255, 1.0) else NovaRGBA(255, 255, 255, 1.0)
        statusSuccessBg -> if (dark) NovaRGBA(21, 58, 36, 1.0) else NovaRGBA(234, 251, 239, 1.0)
        statusSuccessInk -> if (dark) NovaRGBA(95, 224, 138, 1.0) else NovaRGBA(15, 122, 52, 1.0)
        statusSuccessDot -> if (dark) NovaRGBA(46, 210, 86, 1.0) else NovaRGBA(31, 168, 69, 1.0)
        statusWarningBg -> if (dark) NovaRGBA(61, 47, 20, 1.0) else NovaRGBA(255, 246, 232, 1.0)
        statusWarningInk -> if (dark) NovaRGBA(240, 190, 106, 1.0) else NovaRGBA(164, 112, 15, 1.0)
        statusWarningDot -> if (dark) NovaRGBA(232, 161, 58, 1.0) else NovaRGBA(214, 139, 25, 1.0)
        statusDangerBg -> if (dark) NovaRGBA(61, 30, 28, 1.0) else NovaRGBA(255, 238, 236, 1.0)
        statusDangerInk -> if (dark) NovaRGBA(255, 139, 129, 1.0) else NovaRGBA(201, 56, 44, 1.0)
        statusDangerDot -> if (dark) NovaRGBA(224, 69, 59, 1.0) else NovaRGBA(224, 69, 59, 1.0)
        statusInfoBg -> if (dark) NovaRGBA(32, 36, 74, 1.0) else NovaRGBA(238, 240, 255, 1.0)
        statusInfoInk -> if (dark) NovaRGBA(154, 164, 255, 1.0) else NovaRGBA(63, 75, 196, 1.0)
        statusInfoDot -> if (dark) NovaRGBA(91, 140, 247, 1.0) else NovaRGBA(75, 87, 214, 1.0)
        statusNeutralBg -> if (dark) NovaRGBA(38, 38, 43, 1.0) else NovaRGBA(244, 244, 245, 1.0)
        statusNeutralInk -> if (dark) NovaRGBA(168, 168, 174, 1.0) else NovaRGBA(92, 92, 99, 1.0)
        statusNeutralDot -> if (dark) NovaRGBA(107, 107, 114, 1.0) else NovaRGBA(180, 180, 186, 1.0)
    }
}

data class NovaTypeSpec(val fontName: String, val weight: Int, val size: Double, val tracking: Double, val lineHeight: Double)

enum class NovaTypeToken {
    screenTitle, sheetTitle, dialogTitle, brand, sectionTitle, cardTitle, button, buttonSm, body, bodyStrong, label, meta, metaQuiet, badge, tab, overline, micro;

    val spec: NovaTypeSpec get() = when (this) {
        screenTitle -> NovaTypeSpec("PlusJakartaSans-ExtraBold", 800, 22.0, -0.5, 28.0)
        sheetTitle -> NovaTypeSpec("PlusJakartaSans-ExtraBold", 800, 19.0, -0.4, 25.0)
        dialogTitle -> NovaTypeSpec("PlusJakartaSans-ExtraBold", 800, 16.5, -0.3, 22.0)
        brand -> NovaTypeSpec("PlusJakartaSans-ExtraBold", 800, 18.0, -0.3, 23.0)
        sectionTitle -> NovaTypeSpec("PlusJakartaSans-ExtraBold", 800, 14.0, -0.1, 19.0)
        cardTitle -> NovaTypeSpec("PlusJakartaSans-Bold", 700, 14.0, -0.2, 17.5)
        button -> NovaTypeSpec("PlusJakartaSans-Bold", 700, 15.0, 0.0, 20.0)
        buttonSm -> NovaTypeSpec("PlusJakartaSans-Bold", 700, 13.5, 0.0, 18.0)
        body -> NovaTypeSpec("PlusJakartaSans-Medium", 500, 13.0, 0.0, 18.0)
        bodyStrong -> NovaTypeSpec("PlusJakartaSans-SemiBold", 600, 12.5, 0.0, 17.0)
        label -> NovaTypeSpec("PlusJakartaSans-Bold", 700, 12.0, 0.0, 16.0)
        meta -> NovaTypeSpec("PlusJakartaSans-SemiBold", 600, 11.5, 0.0, 15.5)
        metaQuiet -> NovaTypeSpec("PlusJakartaSans-Regular", 400, 12.0, 0.0, 16.0)
        badge -> NovaTypeSpec("PlusJakartaSans-Bold", 700, 10.5, 0.0, 14.0)
        tab -> NovaTypeSpec("PlusJakartaSans-Bold", 700, 9.5, 0.1, 13.0)
        overline -> NovaTypeSpec("PlusJakartaSans-ExtraBold", 800, 10.5, 0.5, 14.0)
        micro -> NovaTypeSpec("PlusJakartaSans-ExtraBold", 800, 9.5, 0.6, 13.0)
    }
}

enum class NovaDimensionToken {
    radiusXs, radiusSm, radiusMd, radiusControl, radiusField, radiusChip, radiusCard, radiusPopover, radiusDialog, radiusSheet, radiusTabBar, radiusPill, spaceScreenX, spaceXs, spaceSm, spaceMd, spaceLg, spaceXl, space2xl, layoutTabBarHeight, layoutTabBarInset, layoutTabBarBottom, layoutScrollBottomInset, layoutScrollTopInset, layoutDeviceWidth, layoutDeviceHeight;

    val value: Double get() = when (this) {
        radiusXs -> 5.0
        radiusSm -> 7.0
        radiusMd -> 12.0
        radiusControl -> 14.0
        radiusField -> 16.0
        radiusChip -> 22.0
        radiusCard -> 22.0
        radiusPopover -> 26.0
        radiusDialog -> 28.0
        radiusSheet -> 32.0
        radiusTabBar -> 34.0
        radiusPill -> 999.0
        spaceScreenX -> 20.0
        spaceXs -> 4.0
        spaceSm -> 7.0
        spaceMd -> 10.0
        spaceLg -> 14.0
        spaceXl -> 18.0
        space2xl -> 24.0
        layoutTabBarHeight -> 66.0
        layoutTabBarInset -> 14.0
        layoutTabBarBottom -> 26.0
        layoutScrollBottomInset -> 122.0
        layoutScrollTopInset -> 58.0
        layoutDeviceWidth -> 402.0
        layoutDeviceHeight -> 874.0
    }
}
