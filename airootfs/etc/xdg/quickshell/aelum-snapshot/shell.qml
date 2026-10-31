// SPDX-License-Identifier: GPL-3.0
//
// aelum-snapshot-prompt - the question a snapshot boot asks.
//
// This system booted a snapshot: the boot menu offered a previous state and the
// user chose it. A snapshot boot is read-only and non-destructive - rebooting out
// of it loses nothing - so the only thing worth doing from inside one is making it
// the system again. That is snapper rollback, and this is the permission request.
//
// It ships in the live ISO and the installer copies it into the installed system
// unchanged, so the live session and the installed system ask the same question in
// the same words. It runs only on a snapshot boot: aelum-snapshot-prompt.service
// is gated on the marker the aelum-snapshot-state generator writes, and the
// snapshot number comes through that same file (EnvironmentFile), together with
// the phrase and date the boot menu titled that snapshot with - added by
// aelum-refind-snapshots - so the question names the state by the very words it
// was chosen with. OK runs /usr/local/bin/aelum-snapshot-restore
// through pkexec - the polkit action shipped beside this file grants it to the
// local, active session of an admin user, which is exactly the session of the
// person who chose OK; everywhere else it is refused. CANCEL closes and changes
// nothing, which is the point of a snapshot boot.
//
// It is a real window, not a layer surface: the seeded Hyprland config floats and
// centers it by its title, and pressing the card body starts the compositor's own
// move request, so the dialog can be dragged out of the way. Only a real user
// session pulls it in - the greeter is not asked.
//
// The colors are the user's live Dux Shell scheme, read from
// ~/.cache/dms/dms-colors.json - the file DMS writes whenever matugen recolors the
// desktop - watched for changes, so the dialog is the current theme in whichever
// mode (dark or light) the desktop is in, and recolors live if the theme changes
// while it is open. Only when that file is missing or unreadable does it fall back
// to the seeded brand scheme at /etc/skel, which is the same file the installer
// seeds every home from, so this dialog owns no palette of its own.
//
// The words are the user's language. They come from i18n/<locale>.json next to
// this file - the snapshot.prompt.* namespace of the installer's own translations,
// extracted there by installer/backend/scripts/gen-snapshot-prompt-i18n.go - and
// the locale is the one this session is running in, resolved when the dialog
// starts. Nothing about the language was decided at install time: change the
// system's locale and the next snapshot boot asks in the new one. A snapshot
// carries its own copy of this directory inside its root, so an old state asks in
// the language it was taken with.

import Quickshell
import Quickshell.Io
import QtQuick

Scope {
  id: prompt

  // The number the unit's EnvironmentFile carried in. 0 means "a snapshot,
  // number unknown" - the marker's existence is the fact, the number is detail.
  property int snapshot: parseInt(Quickshell.env("SNAPSHOT") || "0", 10) || 0

  // The words the boot menu used for this snapshot: aelum-refind-snapshots adds
  // to the marker the same phrase and date it put in the menu title for the
  // booted snapshot. They are data, not copy - the dialog shows them as they
  // are - and they are what the person picked this state out of the menu with,
  // so the question asks with them. Both are optional: an older system's marker,
  // or a snapshot whose info.xml could not be read, leaves the question at the
  // number alone.
  property string snapshotPhrase: (Quickshell.env("SNAPSHOT_PHRASE") || "").trim()
  property string snapshotDate: (Quickshell.env("SNAPSHOT_DATE") || "").trim()
  readonly property string metaLine: {
    const parts = [];
    if (prompt.snapshotPhrase !== "") {
      parts.push(prompt.snapshotPhrase);
    }
    if (prompt.snapshotDate !== "") {
      parts.push(prompt.snapshotDate);
    }
    return parts.join(" · ");
  }

  // The dialog's whole state: ask, then the result of pressing OK.
  property string phase: "ask"
  property string detail: ""

  // ── The copy, in the language this session is running in ────────────────
  //
  // Keys are the installer's snapshot.prompt.* translation namespace, shipped
  // verbatim so a key in the installed system is the key in the installer's
  // catalog. The defaults below are the English of that namespace, kept as the
  // last resort so a dialog with no readable i18n file is still a dialog.
  readonly property string copyPrefix: "snapshot.prompt."
  readonly property string copyDir: "i18n"
  readonly property string systemCopyDir: "/etc/xdg/quickshell/aelum-snapshot/i18n"

  readonly property var copyDefaults: ({
    "title": "You booted snapshot {n}",
    "titleUnknown": "You booted a snapshot",
    "question": "Restore this state as the system?",
    "body": "The system you were using is kept as an undo snapshot, and the "
        + "restored state boots after a reboot. Nothing changes until you press OK.",
    "restoring": "Restoring…",
    "restored": "Restored. The restored system boots on the next reboot.",
    "failed": "Restore failed: {detail}",
    "failedUnknown": "aelum-snapshot-restore exited with an error",
    "cancel": "Cancel",
    "ok": "OK",
    "close": "Close",
    "reboot": "Reboot now"
  })

  // The locales written right to left. They are the installer's own RTL set; the
  // dialog mirrors its layout for them (see card.LayoutMirroring) so a right-to-
  // left language does not end up with left-aligned text and a footer on the wrong
  // side of the card.
  readonly property var rtlLocales: ({ "ar-SA": true, "he-IL": true, "fa-IR": true })

  FileView {
    id: localeConf
    path: "/etc/locale.conf"
    printErrors: false
  }

  // What this session was started with, and the system's own choice after it.
  // systemd imports /etc/locale.conf into the environment it hands its services,
  // and the installer writes that file with the language the install was run in,
  // so the two normally agree; the file is the fallback for a session that was
  // started without a locale of its own.
  property string rawLocale: {
    const fromEnv = (Quickshell.env("LC_ALL") || Quickshell.env("LC_MESSAGES") || Quickshell.env("LANG") || "").trim();
    if (fromEnv !== "") {
      return fromEnv;
    }
    const lines = String(localeConf.text() || "").split("\n");
    for (let i = 0; i < lines.length; i++) {
      const match = lines[i].match(/^\s*LANG=(.*)$/);
      if (match) {
        return match[1].trim();
      }
    }
    return "";
  }

  // de_DE.UTF-8 -> de-DE, eo.UTF-8 -> eo: the same mechanical mapping between the
  // POSIX form and the BCP 47 codes the translation files are named with. C/POSIX
  // is not a language, so it asks in English.
  function localeCode(raw) {
    let code = String(raw || "").trim();
    code = code.replace(/@.*$/, "").replace(/\.(utf-?8|utf-?16|ucs.?2|latin.?1|ascii)$/i, "");
    code = code.replace(/_/g, "-");
    if (code === "" || code === "C" || code === "POSIX") {
      return "en-US";
    }
    return code;
  }

  readonly property string locale: localeCode(prompt.rawLocale)
  readonly property bool isRtl: prompt.rtlLocales[prompt.locale] === true

  // This config's own i18n directory first (so a user's copy of the whole config
  // in ~/.config brings its own strings with it), the system directory after it,
  // then English. A missing file is not an error to complain about: FileView
  // returns nothing for it and the next source is tried.
  function configPath(rel) {
    const url = String(Qt.resolvedUrl(rel));
    return url.startsWith("file://") ? url.slice(7) : url;
  }

  FileView {
    id: ownCopyFile
    path: prompt.configPath(prompt.copyDir + "/" + prompt.locale + ".json")
    printErrors: false
  }

  FileView {
    id: systemCopyFile
    path: prompt.systemCopyDir + "/" + prompt.locale + ".json"
    printErrors: false
  }

  FileView {
    id: englishCopyFile
    path: prompt.systemCopyDir + "/en-US.json"
    printErrors: false
  }

  function parseJson(text) {
    try {
      const parsed = JSON.parse(text);
      return parsed && typeof parsed === "object" ? parsed : null;
    } catch (e) {
      return null;
    }
  }

  property var copyData: {
    return prompt.parseJson(ownCopyFile.text())
        || prompt.parseJson(systemCopyFile.text())
        || prompt.parseJson(englishCopyFile.text());
  }

  // One lookup, one interpolation. {n} is the snapshot number, {detail} the
  // helper's own line; both are spelled the way the installer's frontend spells
  // its placeholders, because these strings are the same strings.
  function tr(key) {
    const shipped = prompt.copyData ? prompt.copyData[prompt.copyPrefix + key] : null;
    const value = shipped || prompt.copyDefaults[key];
    if (!value) {
      return key;
    }
    return String(value).replace(/\{(\w+)\}/g, (match, name) => {
      if (name === "n") {
        return String(prompt.snapshot);
      }
      if (name === "detail") {
        // An empty detail is the case the helper said nothing at all: name that,
        // in the same language as the line around it, instead of leaving the
        // failure text hanging at a colon.
        return prompt.detail || prompt.tr("failedUnknown");
      }
      return "";
    });
  }

  // The live DMS scheme. watchChanges + reload is what makes "always the current
  // DMS colors" true rather than "the colors as of when the dialog opened":
  // matugen recolors DMS by rewriting this file, and the view follows it.
  // printErrors off: a missing file is a supported case (the fallback below),
  // not something to complain about in the logs.
  FileView {
    id: dmsColors
    path: Quickshell.env("HOME") + "/.cache/dms/dms-colors.json"
    watchChanges: true
    onFileChanged: this.reload()
    printErrors: false
  }

  property var dms: prompt.parseJson(dmsColors.text())

  // DMS names its current mode in the same file, so the dialog follows the
  // desktop's dark/light choice rather than guessing from the clock.
  readonly property string dmsMode: (prompt.dms && prompt.dms.mode === "light") ? "light" : "dark"

  // The seeded brand scheme: the very file /etc/skel carries, which is what every
  // home's ~/.cache/dms/dms-colors.json starts as. Used only as the fallback per
  // role, and it holds both modes, so the fallback follows the current one.
  FileView {
    id: seededColors
    path: "/etc/skel/.cache/dms/dms-colors.json"
    printErrors: false
  }

  property var seed: prompt.parseJson(seededColors.text())

  // Both palette files unreadable. Not a palette - one dark surface and white
  // text, enough to read the question and find the buttons.
  readonly property var emergency: ({
    "surface_container": "#1d1b22", "surface_bright": "#1d1b22",
    "on_surface": "#ffffff", "on_surface_variant": "#ffffff",
    "primary": "#1d1b22", "on_primary": "#ffffff",
    "outline_variant": "#ffffff", "error": "#ffffff"
  })

  // One role lookup: the live scheme first, the seeded scheme per role after it.
  // Per role, not per file: a scheme missing one role still renders in the
  // user's colors.
  function color(role) {
    const live = (prompt.dms && prompt.dms.colors) ? prompt.dms.colors[prompt.dmsMode] : null;
    if (live && live[role]) {
      return live[role];
    }
    const seeded = (prompt.seed && prompt.seed.colors) ? prompt.seed.colors[prompt.dmsMode] : null;
    if (seeded && seeded[role]) {
      return seeded[role];
    }
    const seededAny = (prompt.seed && prompt.seed.colors) ? prompt.seed.colors["dark"] : null;
    if (seededAny && seededAny[role]) {
      return seededAny[role];
    }
    return prompt.emergency[role];
  }

  function close() {
    Qt.quit()
  }

  Process {
    id: restoreProc
    // pkexec resolves the helper to the dev.aelum.snapshot.restore action through
    // the policy file's exec.path annotation; the rules file grants it to this
    // session. A denial is an ordinary exit code with polkit's own message on
    // stderr - the failure line below shows it, it is not a silent nothing.
    command: ["pkexec", "/usr/local/bin/aelum-snapshot-restore"]
    onExited: (code) => { prompt.phase = code === 0 ? "done" : "failed"; }
    // Both channels collected so snapper's progress output never blocks on a
    // closed pipe, and its error is the message the failure line shows.
    stdout: StdioCollector { onStreamFinished: prompt.detail = text.trim() }
    stderr: StdioCollector { onStreamFinished: prompt.detail = text.trim() }
  }

  // The REBOOT button is detached on purpose: closing the dialog quits
  // Quickshell, and a tracked child would be killed with it before it reached
  // systemctl. --reboot-only because the OK button's call already rolled back;
  // a second rollback would take a second undo snapshot of a restored system.
  function reboot() {
    Quickshell.execDetached(["pkexec", "/usr/local/bin/aelum-snapshot-restore", "--reboot-only"]);
  }

  // The ask copy, spelled once: it is shown in the ask phase and laid out
  // (hidden) in every other phase, because its height is the space the card
  // reserves so the window never resizes mid-conversation.
  property string askCopy: prompt.tr("question") + "\n\n" + prompt.tr("body")

  FloatingWindow {
    id: dialog
    visible: true

    // The title is the handle the seeded Hyprland config matches its window
    // rule on (float + center): the prompt is a real window, which is what
    // keeps it out of the tile layout and lets the compositor move it. It must
    // stay in sync with that rule.
    title: "aelum-snapshot-prompt"

    // The window is the card. Its width is measured once - from the buttons,
    // which are as wide as their own labels - and fixed from then on, so the text
    // does not reflow while it is being read and the card is sized for the
    // language it is actually asking in. The text block is anchored to the card's
    // top and the buttons to its bottom-right corner, and the body reserves the
    // ask phase's height in every phase (see askBody), so the card keeps one size
    // through the whole flow: pressing OK swaps the buttons in place instead of
    // moving them out from under the hand. A failure detail longer than the
    // ask copy still grows the card.
    property int cardWidth: 540
    property int cardPadding: 28
    property int sidePadding: 32
    property int buttonGap: 24
    property int buttonHeight: 42
    // A button is as wide as its own label plus this padding, with buttonMinWidth
    // as a floor so a short label ("OK") still reads as a button. Text lays out
    // even when invisible, so all four labels are measured in every phase and the
    // window takes the widest footer the whole flow could need - the card never
    // resizes mid-conversation, whatever the language.
    property int buttonMinWidth: 130
    property int buttonLabelPadding: 24
    property int footerWidth: Math.max(
        cancelBtn.implicitWidth + okBtn.implicitWidth + buttons.spacing,
        closeBtn.implicitWidth + rebootBtn.implicitWidth + buttons.spacing)
    implicitWidth: Math.max(cardWidth, footerWidth + 2 * sidePadding)
    implicitHeight: content.height + buttonGap + buttonHeight + 2 * cardPadding

    color: "transparent"

    Rectangle {
      id: card
      anchors.fill: parent
      radius: 18
      color: prompt.color("surface_container")
      border.color: prompt.phase === "failed" ? prompt.color("error") : prompt.color("primary")
      border.width: 2
      focus: true

      // Right-to-left locales: the whole layout mirrors, so the footer reaches for
      // the bottom-left corner and the text aligns the way it is read. Layout-
      // Mirroring is inherited by children, which is why it is set once here, and
      // it mirrors Text's own layout direction too.
      LayoutMirroring.enabled: prompt.isRtl

      // Dragging the dialog: startSystemMove is the compositor-owned move
      // request (xdg_toplevel's start_move, honored by Hyprland 0.56+), so
      // pressing the card body and dragging moves the window like any other -
      // no compositor-side mouse bind needed. The buttons' own MouseAreas are
      // declared after this one and stack above it, so pressing a button never
      // starts a move.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onPressed: dialog.startSystemMove()
      }

      Keys.onEscapePressed: prompt.close()
      Keys.onReturnPressed: {
        if (prompt.phase === "ask") {
          prompt.phase = "restoring";
          restoreProc.running = true;
        } else if (prompt.phase === "done") {
          prompt.reboot();
          prompt.close();
        } else {
          prompt.close();
        }
      }

      Column {
        id: content
        x: dialog.sidePadding
        y: dialog.cardPadding
        width: parent.width - 2 * dialog.sidePadding
        spacing: 16

        Column {
          id: titleBlock
          width: parent.width
          // No gap when there is nothing to gap to: a marker without the
          // enrichment leaves the title block exactly the title.
          spacing: prompt.metaLine !== "" ? 6 : 0

          Text {
            text: prompt.snapshot > 0 ? prompt.tr("title") : prompt.tr("titleUnknown")
            color: prompt.color("on_surface")
            font.pixelSize: 22
            font.bold: true
          }

          Text {
            // The snapshot as the boot menu named it - "Before system update ·
            // 30 Oct 2026 14:02" - the words the person chose it by, shown so
            // the question and the menu entry name the same state. Height 0
            // when empty, so it reserves nothing in a dialog that has no words
            // to show.
            visible: prompt.metaLine !== ""
            width: parent.width
            height: visible ? implicitHeight : 0
            wrapMode: Text.WordWrap
            text: prompt.metaLine
            color: prompt.color("on_surface_variant")
            font.pixelSize: 15
          }
        }

        Text {
          id: bodyText
          width: parent.width
          // Reserve the ask phase's height in every phase: the card keeps one
          // size through the flow and the footer stays anchored where the
          // person already reached for the buttons. A longer failure detail
          // still wins - the reserve is a floor, not a cap.
          height: Math.max(implicitHeight, askBody.height)
          wrapMode: Text.WordWrap
          color: prompt.phase === "failed" ? prompt.color("error") : prompt.color("on_surface_variant")
          font.pixelSize: 15
          text: {
            if (prompt.phase === "ask") {
              return prompt.askCopy;
            }
            if (prompt.phase === "restoring") {
              return prompt.tr("restoring");
            }
            if (prompt.phase === "done") {
              return prompt.tr("restored");
            }
            return prompt.tr("failed");
          }
        }
      }

      // Measurement, not display: the ask copy laid out at the body's width.
      // Text computes its layout even when invisible, so askBody.height is the
      // exact reserve the body takes in the other phases - if the copy or the
      // font changes, the reserve follows it. A translated ask copy is usually
      // taller or shorter than the English one, which is the point: the card is
      // sized for the language it is actually asking in.
      Text {
        id: askBody
        visible: false
        width: content.width
        wrapMode: Text.WordWrap
        font.pixelSize: 15
        text: prompt.askCopy
      }

      // The buttons are a footer: anchored to the card's bottom-right corner -
      // the dialog convention, primary action rightmost - with the fixed gap
      // the height formula above reserves between text and footer. Declared
      // after the card's drag MouseArea, so pressing a button never starts a
      // move, and the empty footer area drags the window like the rest of the
      // card. Under LayoutMirroring the anchors and the row flip together, so
      // the primary action stays on the side a right-to-left reader reaches
      // first.
      Row {
        id: buttons
        anchors.right: parent.right
        anchors.rightMargin: dialog.sidePadding
        anchors.bottom: parent.bottom
        anchors.bottomMargin: dialog.cardPadding
        spacing: 12

        Rectangle {
          id: cancelBtn
          visible: prompt.phase === "ask"
          implicitWidth: Math.max(dialog.buttonMinWidth, cancelLabel.implicitWidth + 2 * dialog.buttonLabelPadding)
          width: implicitWidth
          height: dialog.buttonHeight
          radius: 10
          color: prompt.color("surface_bright")
          border.color: prompt.color("outline_variant")
          Text {
            id: cancelLabel
            anchors.centerIn: parent
            text: prompt.tr("cancel")
            font.capitalization: Font.AllUppercase
            color: prompt.color("on_surface")
            font.pixelSize: 15
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: prompt.close()
          }
        }

        Rectangle {
          id: okBtn
          visible: prompt.phase === "ask"
          implicitWidth: Math.max(dialog.buttonMinWidth, okLabel.implicitWidth + 2 * dialog.buttonLabelPadding)
          width: implicitWidth
          height: dialog.buttonHeight
          radius: 10
          color: prompt.color("primary")
          Text {
            id: okLabel
            anchors.centerIn: parent
            text: prompt.tr("ok")
            font.capitalization: Font.AllUppercase
            color: prompt.color("on_primary")
            font.pixelSize: 15
            font.bold: true
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              prompt.phase = "restoring";
              restoreProc.running = true;
            }
          }
        }

        Rectangle {
          id: closeBtn
          visible: prompt.phase === "done" || prompt.phase === "failed"
          implicitWidth: Math.max(dialog.buttonMinWidth, closeLabel.implicitWidth + 2 * dialog.buttonLabelPadding)
          width: implicitWidth
          height: dialog.buttonHeight
          radius: 10
          color: prompt.color("surface_bright")
          border.color: prompt.color("outline_variant")
          Text {
            id: closeLabel
            anchors.centerIn: parent
            text: prompt.tr("close")
            font.capitalization: Font.AllUppercase
            color: prompt.color("on_surface")
            font.pixelSize: 15
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: prompt.close()
          }
        }

        Rectangle {
          id: rebootBtn
          visible: prompt.phase === "done"
          implicitWidth: Math.max(dialog.buttonMinWidth, rebootLabel.implicitWidth + 2 * dialog.buttonLabelPadding)
          width: implicitWidth
          height: dialog.buttonHeight
          radius: 10
          color: prompt.color("primary")
          Text {
            id: rebootLabel
            anchors.centerIn: parent
            text: prompt.tr("reboot")
            font.capitalization: Font.AllUppercase
            color: prompt.color("on_primary")
            font.pixelSize: 15
            font.bold: true
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              prompt.reboot();
              prompt.close();
            }
          }
        }
      }
    }
  }

  // Answering is the whole job; once the dialog is gone the process has nothing
  // left to do.
  Connections {
    target: Quickshell
    function onLastWindowClosed() {
      Qt.quit();
    }
  }
}
