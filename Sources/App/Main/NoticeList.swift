// Permission notices and errors above the source picker; each hides itself once resolved.

import SwiftUI

struct NoticeList: View {
    @EnvironmentObject var model: RecorderModel

    var body: some View {
        let t = model.t
        VStack(spacing: 8) {
            if model.showsScreenNotice {
                NoticeBanner(icon: "rectangle.dashed.badge.record", title: t("perm.screen.title"), message: t("perm.screen.message"),
                             actionTitle: t("perm.open"), action: { model.openPrivacySettings("Privacy_ScreenCapture") },
                             dismissLabel: t("notice.dismiss"), onDismiss: { model.dismiss(.screen) })
            }
            if model.showsMicNotice {
                NoticeBanner(icon: "mic.slash", title: t("perm.mic.title"), message: t("perm.mic.message"),
                             actionTitle: t("perm.open"), action: { model.openPrivacySettings("Privacy_Microphone") },
                             dismissLabel: t("notice.dismiss"), onDismiss: { model.dismiss(.mic) })
            }
            if let message = problemMessage {
                NoticeBanner(icon: "exclamationmark.triangle", title: t("error.title"), message: message,
                             actionTitle: nil, action: {}, dismissLabel: t("notice.dismiss"), onDismiss: { model.dismiss(.problem) })
            }
        }
        .calmAnimation(value: model.showsScreenNotice)
        .calmAnimation(value: model.showsMicNotice)
        .calmAnimation(value: model.problem)
    }

    private var problemMessage: String? {
        let t = model.t
        switch model.problem {
        case .appNotRunning(let id): return t("error.appNotRunning", model.appName(id))
        case .startTimedOut: return t("error.timeout")
        case .failed(let detail): return t("error.failed", detail)
        default: return nil
        }
    }
}
