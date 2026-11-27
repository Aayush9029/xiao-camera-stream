import SwiftUI

struct AgentsPane: View {
    @State private var tool = CommandLineTool()
    @State private var skill = SkillInstaller()

    var body: some View {
        SettingsForm {
            Section("Command Line Tool") {
                LabeledContent {
                    if tool.isInstalled {
                        HStack {
                            Label("Installed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Button("Uninstall") { Task { await tool.uninstall() } }
                        }
                    } else {
                        Button("Install") { Task { await tool.install() } }
                    }
                } label: {
                    Text(CommandLineTool.name)
                        .font(.body.monospaced())
                }
                Text("Adds a xiaocam command to \(CommandLineTool.linkDisplayPath). Coding agents such as Claude Code and Codex use it to see through the camera.")
                    .settingFootnote()
                if tool.isInstalled, !tool.isLinkDirectoryOnPath {
                    Text("\(CommandLineTool.linkDisplayPath) is not on your PATH. Add this line to ~/.zshrc: export PATH=\"$HOME/.local/bin:$PATH\"")
                        .settingFootnote()
                        .textSelection(.enabled)
                }
                if let failureMessage = tool.failureMessage {
                    Label(failureMessage, systemImage: "exclamationmark.triangle.fill")
                        .settingFootnote()
                        .foregroundStyle(.orange)
                }
            }

            Section("Commands") {
                command("xiaocam status", "Camera state, mode, and signal")
                command("xiaocam snap", "Take a photo and print its path")
                command("xiaocam grid --every 5 --for 30", "Photos over time in one image")
                command("xiaocam clip --for 10", "A short video")
                command("xiaocam mode quality", "Full 3 MP detail")
                command("xiaocam set brightness=1", "Change a sensor setting")
                command("xiaocam jobs", "Captures that run or wait")
            }

            Section("Skill") {
                LabeledContent {
                    switch skill.state {
                    case .installed:
                        HStack {
                            Label("Installed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Button("Reinstall", action: skill.install)
                        }
                    case .outdated:
                        Button("Update Skill", action: skill.install)
                    case .notInstalled:
                        Button("Install Skill", action: skill.install)
                    case .missingFromBundle:
                        Text("Not in this build")
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("xiaocam")
                        .font(.body.monospaced())
                }
                Text("Copies the xiaocam skill to \(SkillInstaller.displayPath). The skill teaches an agent when to snap, when to watch over time, and how to read the results.")
                    .settingFootnote()
                if let failureMessage = skill.failureMessage {
                    Label(failureMessage, systemImage: "exclamationmark.triangle.fill")
                        .settingFootnote()
                        .foregroundStyle(.orange)
                }
            }
        }
        .task {
            skill.refresh()
            await tool.refresh()
        }
    }

    private func command(_ command: String, _ summary: String) -> some View {
        LabeledContent {
            Text(summary)
        } label: {
            Text(command)
                .font(.body.monospaced())
                .textSelection(.enabled)
        }
    }
}
