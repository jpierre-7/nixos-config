# Keeps hints (`f`), scrolling and userscripts working after a tab follows a
# redirect to another site. On Qt 6.11, scripts added to a tab's own page are
# sometimes never run there (qutebrowser#8925), so `f` fails with "Unknown
# error while getting elements". Scripts added to the profile always run, the
# workaround from qutebrowser#7662. Remove this when upstream fixes it.
#
# Patched in late_init, because the webengine modules can't be imported while
# config.py loads. Profile scripts are shared by all tabs, so each name is
# removed before it is added again, to keep one copy.
from qutebrowser.config import configinit

_late_init = configinit.late_init


def late_init(*args, **kwargs):
    from qutebrowser.browser.webengine import webenginetab, webview

    webview.WebEnginePage.scripts = lambda self: self.profile().scripts()
    inject_js = webenginetab._WebEngineScripts._inject_js

    def inject_js_once(self, name, *args, **kwargs):
        self._remove_js(name)
        inject_js(self, name, *args, **kwargs)

    webenginetab._WebEngineScripts._inject_js = inject_js_once
    _late_init(*args, **kwargs)


configinit.late_init = late_init
