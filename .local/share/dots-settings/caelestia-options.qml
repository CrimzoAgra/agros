// Caelestia's options as the installed Caelestia defines them, for the Settings app's "All Caelestia options" (run by
// dots-settings with Qt's qml tool, offscreen, in a throwaway config folder: nothing of yours is read or written).
// Each option of its config (shell.json) and of its sizes (shell-tokens.json): its path, type and default.
// Printed as one line: OPTIONS {"shell": [...], "tokens": [...]}
import QtQuick
import Caelestia.Config

Item {
    function walk(node, prefix, out) {
        for (const k in node) {
            if (typeof node[k] === "function" || k === "objectName") // (a property's change signal is a function)
                continue;
            const d = node.descriptorFor(k);
            if (!d.type)
                continue; // (worked out from others, not an option: rounding.small...)
            const key = prefix ? `${prefix}.${k}` : k;
            if (d.isNode && d.defaultValue === undefined)
                walk(node[k], key, out);
            else
                out.push({ key, type: d.type, default: d.defaultValue });
        }
        return out;
    }

    Component.onCompleted: {
        try {
            console.log("OPTIONS " + JSON.stringify({ shell: walk(GlobalConfig, "", []), tokens: walk(TokenConfig, "", []) }));
        } finally {
            Qt.quit(); // also after an error: the qml tool otherwise idles until dots-settings' timeout
        }
    }
}
