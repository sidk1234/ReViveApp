import SwiftUI

struct HelpCenterView: View {
    @Environment(\.colorScheme) private var colorScheme

    private let homeChallengeTutorialKey = "revive.tutorial.home.challengeFlow"
    private let homeChallengeReplayPendingKey = "revive.tutorial.home.challengeFlow.replayPending"
    private let homeChallengeReplayRequestedAtKey = "revive.tutorial.home.challengeFlow.replayRequestedAt"
    private let captureFirstRecycleTutorialKey = "revive.tutorial.capture.firstRecycleAction"
    private let binMarkAsRecycledTutorialKey = "revive.tutorial.bin.markAsRecycled"

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient(colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Help")
                        .font(AppType.display(30))
                        .foregroundStyle(.primary)

                    tutorialActionsCard

                    Text("Challenges tutorial starts on Home after the Challenges card appears.")
                        .font(AppType.body(11))
                        .foregroundStyle(.primary.opacity(0.62))
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 120)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var tutorialActionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tutorials")
                .font(AppType.title(16))
                .foregroundStyle(.primary)

            actionButton(
                title: "Beginner Tips",
                subtitle: "Replay the tab walkthrough overlay.",
                icon: "play.circle.fill",
                action: replayMainTabTutorial
            )

            actionButton(
                title: "Challenges Tutorial",
                subtitle: "Home challenges + progress highlight.",
                icon: "flag.checkered.2.crossed",
                action: replayHomeChallengeTutorial
            )

            actionButton(
                title: "Capture Tutorial",
                subtitle: "Mark for Recycle step on Capture.",
                icon: "camera.fill",
                action: replayCaptureRecycleTutorial
            )

            actionButton(
                title: "Bin Tutorial",
                subtitle: "Mark as Recycled step in Bin.",
                icon: "trash.fill",
                action: replayBinMarkTutorial
            )

            actionButton(
                title: "Reset All Tutorials",
                subtitle: "Clears tutorial progress and opens Beginner Tips.",
                icon: "arrow.counterclockwise.circle.fill",
                action: resetAllTutorials
            )
        }
        .padding(16)
        .staticCard(cornerRadius: 20)
    }

    private func actionButton(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppType.title(14))
                    Text(subtitle)
                        .font(AppType.body(11))
                        .foregroundStyle(.primary.opacity(0.7))
                }
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    private func replayMainTabTutorial() {
        NotificationCenter.default.post(name: .reviveOpenTutorial, object: nil)
    }

    private func replayHomeChallengeTutorial() {
        UserDefaults.standard.removeObject(forKey: homeChallengeTutorialKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: homeChallengeReplayRequestedAtKey)
        UserDefaults.standard.set(true, forKey: homeChallengeReplayPendingKey)
        NotificationCenter.default.post(name: .reviveOpenHome, object: nil)
        NotificationCenter.default.post(name: .reviveReplayHomeChallengeTutorial, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NotificationCenter.default.post(name: .reviveReplayHomeChallengeTutorial, object: nil)
        }
    }

    private func replayCaptureRecycleTutorial() {
        UserDefaults.standard.removeObject(forKey: captureFirstRecycleTutorialKey)
        NotificationCenter.default.post(name: .reviveOpenCapture, object: nil)
    }

    private func replayBinMarkTutorial() {
        UserDefaults.standard.removeObject(forKey: binMarkAsRecycledTutorialKey)
        NotificationCenter.default.post(name: .reviveOpenBin, object: nil)
    }

    private func resetAllTutorials() {
        UserDefaults.standard.removeObject(forKey: homeChallengeTutorialKey)
        UserDefaults.standard.removeObject(forKey: homeChallengeReplayPendingKey)
        UserDefaults.standard.removeObject(forKey: homeChallengeReplayRequestedAtKey)
        UserDefaults.standard.removeObject(forKey: captureFirstRecycleTutorialKey)
        UserDefaults.standard.removeObject(forKey: binMarkAsRecycledTutorialKey)
        replayMainTabTutorial()
    }
}
