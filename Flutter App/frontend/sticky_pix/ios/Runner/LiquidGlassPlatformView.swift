import Flutter
import SwiftUI
import UIKit

/// Hosts StickyPix's iOS-only home controls as one native layer above Flutter.
///
/// Keeping the controls in a root-level sibling view allows Liquid Glass to
/// sample the Flutter and Thermion scene underneath. An embedded platform view
/// cannot provide that compositing context and renders as a flat gray surface.
final class LiquidGlassOverlayPlugin: NSObject, FlutterPlugin {
  static let channelName = "stickypix/native_liquid_glass_overlay"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = LiquidGlassOverlayPlugin(
      channel: channel,
      viewController: registrar.viewController
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  private let channel: FlutterMethodChannel
  private weak var viewController: UIViewController?
  private let model = LiquidGlassHomeModel()
  private var hostingController: UIHostingController<LiquidGlassHomeOverlay>?
  private var heightConstraint: NSLayoutConstraint?
  private var topHostingController: UIHostingController<LiquidGlassTopControls>?
  private var topHeightConstraint: NSLayoutConstraint?
  private var topOffsetConstraint: NSLayoutConstraint?

  private init(channel: FlutterMethodChannel, viewController: UIViewController?) {
    self.channel = channel
    self.viewController = viewController
    super.init()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "show":
      guard let arguments = call.arguments as? [String: Any] else {
        result(
          FlutterError(
            code: "invalid_state",
            message: "Liquid Glass state must be a map.",
            details: nil
          )
        )
        return
      }
      model.apply(arguments)
      installOverlayIfNeeded()
      installTopOverlayIfNeeded()
      updateOverlayHeight()
      updateTopOverlayLayout()
      result(nil)
    case "hide":
      removeOverlay()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func installOverlayIfNeeded() {
    guard hostingController == nil, let parent = resolvedViewController() else {
      return
    }

    let overlay = LiquidGlassHomeOverlay(model: model) { [weak self] action, payload in
      var arguments = payload
      arguments["action"] = action
      self?.channel.invokeMethod("action", arguments: arguments)
    }
    let hostingController = UIHostingController(rootView: overlay)
    let overlayView = hostingController.view!
    overlayView.backgroundColor = .clear
    overlayView.isOpaque = false
    overlayView.translatesAutoresizingMaskIntoConstraints = false

    parent.addChild(hostingController)
    parent.view.addSubview(overlayView)
    let heightConstraint = overlayView.heightAnchor.constraint(
      equalToConstant: model.compact ? 267 : 271
    )
    NSLayoutConstraint.activate([
      overlayView.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
      overlayView.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
      overlayView.bottomAnchor.constraint(equalTo: parent.view.safeAreaLayoutGuide.bottomAnchor),
      heightConstraint,
    ])
    hostingController.didMove(toParent: parent)

    self.hostingController = hostingController
    self.heightConstraint = heightConstraint
  }

  private func resolvedViewController() -> UIViewController? {
    if let viewController { return viewController }
    let root = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)?
      .rootViewController
    viewController = root
    return root
  }

  private func updateOverlayHeight() {
    heightConstraint?.constant = model.compact ? 267 : 271
  }

  private func installTopOverlayIfNeeded() {
    guard topHostingController == nil, let parent = resolvedViewController() else {
      return
    }

    let overlay = LiquidGlassTopControls(model: model) { [weak self] action, payload in
      var arguments = payload
      arguments["action"] = action
      self?.channel.invokeMethod("action", arguments: arguments)
    }
    let hostingController = UIHostingController(rootView: overlay)
    let overlayView = hostingController.view!
    overlayView.backgroundColor = .clear
    overlayView.isOpaque = false
    overlayView.translatesAutoresizingMaskIntoConstraints = false

    parent.addChild(hostingController)
    parent.view.addSubview(overlayView)
    let heightConstraint = overlayView.heightAnchor.constraint(
      equalToConstant: model.compact ? 94 : 96
    )
    let topOffsetConstraint = overlayView.topAnchor.constraint(
      equalTo: parent.view.safeAreaLayoutGuide.topAnchor,
      constant: model.compact ? 36 : 44
    )
    NSLayoutConstraint.activate([
      overlayView.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
      overlayView.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
      topOffsetConstraint,
      heightConstraint,
    ])
    hostingController.didMove(toParent: parent)

    self.topHostingController = hostingController
    self.topHeightConstraint = heightConstraint
    self.topOffsetConstraint = topOffsetConstraint
  }

  private func updateTopOverlayLayout() {
    topHeightConstraint?.constant = model.compact ? 94 : 96
    topOffsetConstraint?.constant = model.compact ? 36 : 44
  }

  private func removeOverlay() {
    guard let hostingController else { return }
    hostingController.willMove(toParent: nil)
    hostingController.view.removeFromSuperview()
    hostingController.removeFromParent()
    self.hostingController = nil
    heightConstraint = nil

    if let topHostingController {
      topHostingController.willMove(toParent: nil)
      topHostingController.view.removeFromSuperview()
      topHostingController.removeFromParent()
    }
    self.topHostingController = nil
    topHeightConstraint = nil
    topOffsetConstraint = nil
  }
}

private final class LiquidGlassHomeModel: ObservableObject {
  @Published var preset = "4 Gray"
  @Published var fileSize = "—"
  @Published var deviceName = "StickyPix"
  @Published var status = "Not connected"
  @Published var isReady = false
  @Published var batteryLevel: Int?
  @Published var lastUpdated = "Not synced yet"
  @Published var canSend = false
  @Published var progress = 0
  @Published var selectedDestination = "home"
  @Published var mode = "fourGray"
  @Published var canEdit = false
  @Published var canPick = true
  @Published var imageLabel = "Pick Image"
  @Published var compact = false
  @Published var previewImage: UIImage?

  func apply(_ arguments: [String: Any]) {
    preset = arguments["preset"] as? String ?? preset
    fileSize = arguments["fileSize"] as? String ?? fileSize
    deviceName = arguments["deviceName"] as? String ?? deviceName
    status = arguments["status"] as? String ?? status
    isReady = arguments["isReady"] as? Bool ?? isReady
    batteryLevel = (arguments["batteryLevel"] as? NSNumber)?.intValue
    lastUpdated = arguments["lastUpdated"] as? String ?? lastUpdated
    canSend = arguments["canSend"] as? Bool ?? canSend
    progress = (arguments["progress"] as? NSNumber)?.intValue ?? progress
    selectedDestination =
      arguments["selectedDestination"] as? String ?? selectedDestination
    mode = arguments["mode"] as? String ?? mode
    canEdit = arguments["canEdit"] as? Bool ?? canEdit
    canPick = arguments["canPick"] as? Bool ?? canPick
    imageLabel = arguments["imageLabel"] as? String ?? imageLabel
    compact = arguments["compact"] as? Bool ?? compact
    if let data = arguments["previewPng"] as? FlutterStandardTypedData {
      previewImage = UIImage(data: data.data)
    } else {
      previewImage = nil
    }
  }
}

private struct LiquidGlassHomeOverlay: View {
  @ObservedObject var model: LiquidGlassHomeModel
  let onAction: (String, [String: Any]) -> Void

  var body: some View {
    Group {
      if #available(iOS 26.0, *) {
        GlassEffectContainer(spacing: 12) {
          layout(usesNativeGlass: true)
        }
      } else {
        layout(usesNativeGlass: false)
      }
    }
    .padding(.horizontal, 16)
    .preferredColorScheme(.dark)
    .accessibilityElement(children: .contain)
  }

  private func layout(usesNativeGlass: Bool) -> some View {
    VStack(spacing: 0) {
      ProcessingSummary(model: model)
        .frame(maxWidth: 353)
        .frame(height: model.compact ? 59 : 61)
        .modifier(
          LiquidGlassSurface(
            cornerRadius: 13,
            interactive: false,
            enabled: usesNativeGlass
          )
        )

      Spacer().frame(height: model.compact ? 8 : 10)

      DeviceTransferIsland(model: model) {
        onAction("send", [:])
      }
      .frame(height: 98)
      .modifier(
        LiquidGlassSurface(
          cornerRadius: 20,
          interactive: false,
          enabled: usesNativeGlass
        )
      )

      Spacer().frame(height: 12)

      PrimaryNavigationIsland(
        selectedDestination: model.selectedDestination
      ) { destination in
        onAction("destination", ["destination": destination])
      }
      .frame(height: 72)
      .modifier(
        LiquidGlassSurface(
          cornerRadius: 30,
          interactive: true,
          enabled: usesNativeGlass
        )
      )

      Spacer().frame(height: 18)
    }
  }
}

private struct LiquidGlassTopControls: View {
  @ObservedObject var model: LiquidGlassHomeModel
  let onAction: (String, [String: Any]) -> Void

  var body: some View {
    Group {
      if #available(iOS 26.0, *) {
        GlassEffectContainer(spacing: 8) {
          controls(usesNativeGlass: true)
        }
      } else {
        controls(usesNativeGlass: false)
      }
    }
    .padding(.horizontal, 16)
    .preferredColorScheme(.dark)
  }

  private func controls(usesNativeGlass: Bool) -> some View {
    VStack(spacing: model.compact ? 6 : 8) {
      HStack(spacing: 8) {
        modeButton(
          title: "4 Gray",
          icon: "circle.lefthalf.filled",
          mode: "fourGray",
          selected: model.mode == "fourGray",
          usesNativeGlass: usesNativeGlass
        )
        modeButton(
          title: "6 Color",
          icon: "paintpalette",
          mode: "sixColor",
          selected: model.mode == "sixColor",
          usesNativeGlass: usesNativeGlass
        )
      }
      .frame(width: 239, height: 36)

      HStack(spacing: 8) {
        actionButton(
          title: "Edit",
          icon: "slider.horizontal.3",
          enabled: model.canEdit,
          usesNativeGlass: usesNativeGlass
        ) {
          onAction("edit", [:])
        }
        actionButton(
          title: model.imageLabel,
          icon: "photo.on.rectangle",
          enabled: model.canPick,
          usesNativeGlass: usesNativeGlass
        ) {
          onAction("pick", [:])
        }
      }
      .frame(width: 211, height: 39)
    }
    .frame(maxWidth: .infinity)
  }

  private func modeButton(
    title: String,
    icon: String,
    mode: String,
    selected: Bool,
    usesNativeGlass: Bool
  ) -> some View {
    Button {
      onAction("mode", ["mode": mode])
    } label: {
      Label(title, systemImage: icon)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(selected ? Color.primary : Color.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(selected ? accent.opacity(0.16) : .clear, in: Capsule())
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .modifier(
      LiquidGlassSurface(
        cornerRadius: 18,
        interactive: true,
        enabled: usesNativeGlass
      )
    )
  }

  private func actionButton(
    title: String,
    icon: String,
    enabled: Bool,
    usesNativeGlass: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(title, systemImage: icon)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .opacity(enabled ? 1 : 0.42)
    .modifier(
      LiquidGlassSurface(
        cornerRadius: 16,
        interactive: true,
        enabled: usesNativeGlass
      )
    )
  }

  private var accent: Color {
    Color(red: 0.38, green: 0.25, blue: 0.67)
  }
}

private struct LiquidGlassSurface: ViewModifier {
  let cornerRadius: CGFloat
  let interactive: Bool
  let enabled: Bool

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *), enabled {
      if interactive {
        content.glassEffect(
          .regular.interactive(),
          in: .rect(cornerRadius: cornerRadius)
        )
      } else {
        content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
      }
    } else {
      content
        .background(
          .ultraThinMaterial,
          in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(.white.opacity(0.65), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }
  }
}

private struct ProcessingSummary: View {
  @ObservedObject var model: LiquidGlassHomeModel

  var body: some View {
    HStack(spacing: 0) {
      SummaryCell(
        systemName: "waveform.path.ecg",
        value: model.preset,
        label: "Dithering"
      )
      divider
      SummaryCell(
        systemName: "crop",
        value: "400 × 600",
        label: "Resolution"
      )
      divider
      SummaryCell(
        systemName: "circle.grid.3x3.fill",
        value: "180 PPI",
        label: "Display"
      )
      divider
      SummaryCell(
        systemName: "doc",
        value: model.fileSize,
        label: "File Size"
      )
    }
    .padding(.horizontal, 2)
    .foregroundStyle(.primary)
  }

  private var divider: some View {
    Divider()
      .overlay(.secondary.opacity(0.25))
      .padding(.vertical, 7)
  }
}

private struct SummaryCell: View {
  let systemName: String
  let value: String
  let label: String

  var body: some View {
    VStack(spacing: 1) {
      Image(systemName: systemName)
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(Color(red: 0.38, green: 0.25, blue: 0.67))
      Text(value)
        .font(.system(size: 12.5, weight: .bold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Text(label)
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity)
  }
}

private struct DeviceTransferIsland: View {
  @ObservedObject var model: LiquidGlassHomeModel
  let onSend: () -> Void

  var body: some View {
    HStack(spacing: 11) {
      preview
        .frame(width: 71, height: 71)

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 5) {
          Text(model.deviceName)
            .font(.system(size: 19, weight: .bold))
            .lineLimit(1)
          statusPill
        }

        HStack(spacing: 8) {
          Image(systemName: "bluetooth")
            .foregroundStyle(accent)
          Image(systemName: "battery.50percent")
          Text(model.batteryLevel.map { "\($0)%" } ?? "—")
            .font(.system(size: 13, weight: .semibold))
        }
        .font(.system(size: 17))

        Text(model.lastUpdated)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      sendButton
        .frame(width: 72, height: 72)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
  }

  private var preview: some View {
    RoundedRectangle(cornerRadius: 13, style: .continuous)
      .fill(.white.opacity(0.42))
      .overlay {
        Group {
          if let image = model.previewImage {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
          } else {
            Text("sticky pix")
              .font(.system(size: 7))
              .foregroundStyle(accent.opacity(0.65))
          }
        }
        .frame(width: 39, height: 57)
        .background(Color(white: 0.91))
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 3, style: .continuous)
            .stroke(Color.gray.opacity(0.35), lineWidth: 1)
        }
      }
      .overlay {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
          .stroke(.white.opacity(0.7), lineWidth: 1)
      }
  }

  private var statusPill: some View {
    HStack(spacing: 4) {
      Text(model.status)
        .lineLimit(1)
      Circle()
        .fill(model.isReady ? Color.green : Color.gray)
        .frame(width: 7, height: 7)
    }
    .font(.system(size: 10.5, weight: .semibold))
    .foregroundStyle(accent)
    .padding(.horizontal, 6)
    .padding(.vertical, 3)
    .background(accent.opacity(0.12), in: Capsule())
  }

  @ViewBuilder
  private var sendButton: some View {
    let label = VStack(spacing: 1) {
      if model.progress > 0 && model.progress < 100 {
        ProgressView(value: Double(model.progress), total: 100)
          .progressViewStyle(.circular)
          .tint(.white)
          .frame(width: 23, height: 23)
        Text("\(model.progress)%")
      } else {
        Image(systemName: "paperplane")
          .font(.system(size: 23, weight: .medium))
        Text("Send")
      }
    }
    .font(.system(size: 13, weight: .semibold))
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity, maxHeight: .infinity)

    if #available(iOS 26.0, *) {
      Button(action: onSend) { label }
        .buttonStyle(.plain)
        .glassEffect(
          .regular.tint(accent).interactive(),
          in: .circle
        )
        .disabled(!model.canSend)
        .opacity(model.canSend ? 1 : 0.42)
    } else {
      Button(action: onSend) { label }
        .buttonStyle(.plain)
        .background(accent, in: Circle())
        .disabled(!model.canSend)
        .opacity(model.canSend ? 1 : 0.42)
    }
  }

  private var accent: Color {
    Color(red: 0.38, green: 0.25, blue: 0.67)
  }
}

private struct PrimaryNavigationIsland: View {
  let selectedDestination: String
  let onSelect: (String) -> Void

  private let items: [(String, String, String)] = [
    ("me", "person", "Me"),
    ("library", "photo.on.rectangle", "Library"),
    ("home", "house.fill", "Home"),
    ("messages", "bubble.left.and.bubble.right", "Messages"),
    ("devices", "dot.radiowaves.left.and.right", "Devices"),
  ]

  var body: some View {
    HStack(spacing: 0) {
      ForEach(items, id: \.0) { destination, icon, label in
        let selected = selectedDestination == destination
        Button {
          onSelect(destination)
        } label: {
          VStack(spacing: 3) {
            Image(systemName: icon)
              .font(.system(size: selected ? 21 : 20, weight: .medium))
              .frame(height: 24)
            Text(label)
              .font(.system(size: 12, weight: selected ? .bold : .medium))
              .lineLimit(1)
              .minimumScaleFactor(0.75)
            Capsule()
              .fill(selected ? accent : .clear)
              .frame(width: selected ? 14 : 0, height: 3)
          }
          .foregroundStyle(selected ? Color.primary : Color.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
      }
    }
  }

  private var accent: Color {
    Color(red: 0.38, green: 0.25, blue: 0.67)
  }
}
