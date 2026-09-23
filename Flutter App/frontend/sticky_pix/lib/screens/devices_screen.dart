import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../product_viewer/product_3d_viewer.dart';
import '../product_viewer/product_model_config.dart';
import '../product_viewer/product_viewer_controller.dart';

/// Hardware-first device management, kept separate from the image composer so
/// it can later read paired-device records rather than the demo data below.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({
    super.key,
    this.latestPreviewPng,
    this.homeDeviceName = 'Bedroom',
    this.onHomeDeviceCustomized,
  });

  final Uint8List? latestPreviewPng;
  final String homeDeviceName;
  final ValueChanged<StickyPixDevice>? onHomeDeviceCustomized;

  static const _initialDevices = <StickyPixDevice>[
    StickyPixDevice(
      id: 'living-room',
      name: 'Living Room',
      kind: StickyPixDeviceKind.fourGray,
      status: StickyPixStatus.ready,
      battery: 65,
      updated: 'Updated 2 min ago',
    ),
    StickyPixDevice(
      id: 'office',
      name: 'Office',
      kind: StickyPixDeviceKind.fourGray,
      status: StickyPixStatus.offline,
      battery: 91,
      updated: 'Updated 1 day ago',
    ),
    StickyPixDevice(
      id: 'bedroom',
      name: 'Bedroom',
      kind: StickyPixDeviceKind.sixColor,
      status: StickyPixStatus.ready,
      battery: 72,
      updated: 'Updated just now',
    ),
    StickyPixDevice(
      id: 'kitchen',
      name: 'Kitchen',
      kind: StickyPixDeviceKind.sixColor,
      status: StickyPixStatus.lowBattery,
      battery: 18,
      updated: 'Updated 3 hrs ago',
    ),
  ];

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late List<StickyPixDevice> _devices;

  @override
  void initState() {
    super.initState();
    _devices = List.of(DevicesScreen._initialDevices);
  }

  @override
  Widget build(BuildContext context) {
    final fourGray = _devices
        .where((device) => device.kind == StickyPixDeviceKind.fourGray)
        .toList(growable: false);
    final sixColor = _devices
        .where((device) => device.kind == StickyPixDeviceKind.sixColor)
        .toList(growable: false);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 122),
                  sliver: SliverList.list(
                    children: [
                      _DevicesHeader(
                        onSettings: () => _showComingSoon(context, 'Settings'),
                        onAdd: () => _showComingSoon(context, 'Add Device'),
                      ),
                      const SizedBox(height: 30),
                      _SectionHeader(
                        title: '4 GRAY DEVICES',
                        count: fourGray.length,
                      ),
                      const SizedBox(height: 16),
                      ...fourGray.indexed.expand(
                        (entry) => [
                          _DeviceCard(
                            device: entry.$2,
                            isHomeDevice:
                                entry.$2.name == widget.homeDeviceName,
                            onCustomize: _customize,
                            displayTexture: entry.$1 == 0
                                ? widget.latestPreviewPng
                                : null,
                          ),
                          const SizedBox(height: 18),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _SectionHeader(
                        title: '6 COLOR DEVICES',
                        count: sixColor.length,
                      ),
                      const SizedBox(height: 16),
                      ...sixColor.indexed.expand(
                        (entry) => [
                          _DeviceCard(
                            device: entry.$2,
                            isHomeDevice:
                                entry.$2.name == widget.homeDeviceName,
                            onCustomize: _customize,
                            displayTexture: entry.$1 == 0
                                ? widget.latestPreviewPng
                                : null,
                          ),
                          const SizedBox(height: 18),
                        ],
                      ),
                      _AddDeviceCard(
                        onTap: () => _showComingSoon(context, 'Add Device'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            _DevicesNavigation(
              onHome: () => Navigator.of(context).pop(),
              onUnavailable: (label) => _showComingSoon(context, label),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _customize(StickyPixDevice device) async {
    final updated = await showModalBottomSheet<StickyPixDevice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DeviceCustomizeSheet(device: device),
    );
    if (updated == null || !mounted) return;
    setState(() {
      _devices = _devices
          .map((item) => item.id == updated.id ? updated : item)
          .toList(growable: false);
    });
    if (device.name == widget.homeDeviceName) {
      widget.onHomeDeviceCustomized?.call(updated);
    }
  }
}

void _showComingSoon(BuildContext context, String label) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('$label is coming soon.'),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

enum StickyPixDeviceKind { fourGray, sixColor }

enum StickyPixStatus { ready, offline, lowBattery }

class StickyPixDevice {
  const StickyPixDevice({
    required this.id,
    required this.name,
    required this.kind,
    required this.status,
    required this.battery,
    required this.updated,
    this.rearShellColor = const Color(0xFF9CC8E8),
    this.cardstockColor = const Color(0xFFF5F5F5),
    this.bezelColor = const Color(0xFFF5F5F5),
    this.kickstandColor = const Color(0xFFF5F5F5),
  });

  final String id;
  final String name;
  final StickyPixDeviceKind kind;
  final StickyPixStatus status;
  final int battery;
  final String updated;
  final Color rearShellColor;

  /// The visible display surround in the GLB (`Cardstock 4`).
  final Color cardstockColor;

  /// The outer front case (`FrontShell …`)—separate from the cardstock bezel.
  final Color bezelColor;
  final Color kickstandColor;

  StickyPixDevice copyWith({
    String? name,
    Color? rearShellColor,
    Color? cardstockColor,
    Color? bezelColor,
    Color? kickstandColor,
  }) => StickyPixDevice(
    id: id,
    name: name ?? this.name,
    kind: kind,
    status: status,
    battery: battery,
    updated: updated,
    rearShellColor: rearShellColor ?? this.rearShellColor,
    cardstockColor: cardstockColor ?? this.cardstockColor,
    bezelColor: bezelColor ?? this.bezelColor,
    kickstandColor: kickstandColor ?? this.kickstandColor,
  );
}

class _DevicesHeader extends StatelessWidget {
  const _DevicesHeader({required this.onSettings, required this.onAdd});
  final VoidCallback onSettings;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Devices',
              style: TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.1,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Manage and customize your StickyPix devices.',
              style: TextStyle(
                color: Color(0xB3FFFFFF),
                fontSize: 17,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 12),
      _CircleAction(
        icon: CupertinoIcons.gear_alt,
        tooltip: 'Settings',
        onTap: onSettings,
      ),
      const SizedBox(width: 10),
      _CircleAction(
        icon: CupertinoIcons.add,
        tooltip: 'Add device',
        onTap: onAdd,
      ),
    ],
  );
}

class _CircleAction extends StatefulWidget {
  const _CircleAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  @override
  State<_CircleAction> createState() => _CircleActionState();
}

class _CircleActionState extends State<_CircleAction> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onTap,
    onTapDown: (_) => setState(() => _pressed = true),
    onTapCancel: () => setState(() => _pressed = false),
    onTapUp: (_) => setState(() => _pressed = false),
    child: Tooltip(
      message: widget.tooltip,
      child: AnimatedScale(
        scale: _pressed ? .96 : 1,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x14FFFFFF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Icon(widget.icon, size: 22, color: Colors.white),
        ),
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});
  final String title;
  final int count;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        title,
        style: const TextStyle(
          color: Color(0xFFE5E5EA),
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.15,
        ),
      ),
      const SizedBox(width: 10),
      Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Color(0xFF1F1F1F),
          shape: BoxShape.circle,
        ),
        child: Text(
          '$count',
          style: const TextStyle(
            color: Color(0xFFE5E5EA),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ],
  );
}

class _DeviceCard extends StatefulWidget {
  const _DeviceCard({
    required this.device,
    required this.isHomeDevice,
    required this.onCustomize,
    this.displayTexture,
  });
  final StickyPixDevice device;
  final bool isHomeDevice;
  final ValueChanged<StickyPixDevice> onCustomize;
  final Uint8List? displayTexture;
  @override
  State<_DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<_DeviceCard> {
  final ProductViewerController _viewerController = ProductViewerController();
  bool _pressed = false;
  @override
  void initState() {
    super.initState();
    final texture = widget.displayTexture;
    if (texture != null) {
      unawaited(_viewerController.setDisplayTexture(texture));
    }
    _applyAppearance();
  }

  @override
  void didUpdateWidget(covariant _DeviceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device != widget.device) _applyAppearance();
  }

  void _applyAppearance() {
    unawaited(
      _viewerController.setPartColor(
        ProductPart.enclosure,
        widget.device.cardstockColor,
      ),
    );
    unawaited(
      _viewerController.setPartColor(
        ProductPart.backShell,
        widget.device.rearShellColor,
      ),
    );
    unawaited(
      _viewerController.setPartColor(
        ProductPart.bezel,
        widget.device.bezelColor,
      ),
    );
    unawaited(
      _viewerController.setPartColor(
        ProductPart.kickstand,
        widget.device.kickstandColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.device.status;
    final statusColor = switch (status) {
      StickyPixStatus.ready => const Color(0xFF34C759),
      StickyPixStatus.offline => const Color(0xFF8E8E93),
      StickyPixStatus.lowBattery => const Color(0xFFFF9F0A),
    };
    final statusText = switch (status) {
      StickyPixStatus.ready => 'Ready',
      StickyPixStatus.offline => 'Offline',
      StickyPixStatus.lowBattery => 'Low Battery',
    };
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        _showComingSoon(context, widget.device.name);
      },
      child: AnimatedScale(
        scale: _pressed ? .99 : 1,
        duration: const Duration(milliseconds: 150),
        child: Container(
          height: 190,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0x0DFFFFFF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x21000000),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 118,
                child: _DeviceModelThumbnail(controller: _viewerController),
              ),
              Container(width: 1, height: 120, color: const Color(0x0FFFFFFF)),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.device.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.35,
                            ),
                          ),
                        ),
                        const Icon(
                          CupertinoIcons.chevron_right,
                          color: Color(0xFFAEAEB2),
                          size: 18,
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          statusText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                        ),
                        const Spacer(),
                        if (widget.isHomeDevice) const _HomeDeviceIndicator(),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          CupertinoIcons.battery_75_percent,
                          color: Colors.white,
                          size: 19,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${widget.device.battery}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      widget.device.updated,
                      style: const TextStyle(
                        color: Color(0x99FFFFFF),
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    const Divider(height: 1, color: Color(0x0FFFFFFF)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _CardButton(
                            icon: CupertinoIcons.slider_horizontal_3,
                            label: 'Customize',
                            onTap: () => widget.onCustomize(widget.device),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _CardButton(
                            icon: CupertinoIcons.gear_alt,
                            label: 'Settings',
                            onTap: () => _showComingSoon(context, 'Settings'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeDeviceIndicator extends StatelessWidget {
  const _HomeDeviceIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 23,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: const Color(0x337C6CF8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x337C6CF8)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.house_fill, color: Color(0xFF9D91FF), size: 11),
          SizedBox(width: 4),
          Text(
            'Home',
            style: TextStyle(
              color: Color(0xFFD7D1FF),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceCustomizeSheet extends StatefulWidget {
  const _DeviceCustomizeSheet({required this.device});
  final StickyPixDevice device;

  @override
  State<_DeviceCustomizeSheet> createState() => _DeviceCustomizeSheetState();
}

class _DeviceCustomizeSheetState extends State<_DeviceCustomizeSheet> {
  static const _swatches = <Color>[
    Color(0xFFF5F5F5),
    Color(0xFF1C1C1E),
    // Dark, saturated finishes keep their character under the bright studio
    // lights used by the 3D product viewer.
    Color(0xFF113A68), // midnight blue
    Color(0xFF1456B8), // cobalt blue
    Color(0xFF00695C), // deep teal
    Color(0xFF1B5E20), // forest green
    Color(0xFF7B1F35), // burgundy
    Color(0xFF5A2D82), // deep plum
    Color(0xFF704000), // walnut amber
  ];

  late final TextEditingController _nameController;
  late Color _rearShell;
  late Color _cardstock;
  late Color _bezel;
  late Color _kickstand;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.device.name);
    _rearShell = widget.device.rearShellColor;
    _cardstock = widget.device.cardstockColor;
    _bezel = widget.device.bezelColor;
    _kickstand = widget.device.kickstandColor;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    Navigator.of(context).pop(
      widget.device.copyWith(
        name: name.isEmpty ? widget.device.name : name,
        rearShellColor: _rearShell,
        cardstockColor: _cardstock,
        bezelColor: _bezel,
        kickstandColor: _kickstand,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        decoration: BoxDecoration(
          color: const Color(0xFF171717),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0x14FFFFFF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x99000000),
              blurRadius: 30,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0x4DFFFFFF),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Customize Device',
              style: TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.w700,
                letterSpacing: -.4,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Personalize the name and finish of this StickyPix.',
              style: TextStyle(color: Color(0x99FFFFFF), fontSize: 14),
            ),
            const SizedBox(height: 20),
            const Text(
              'DEVICE NAME',
              style: TextStyle(
                color: Color(0x99FFFFFF),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF242424),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 14,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0x14FFFFFF)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: Color(0xFF7C6CF8),
                    width: 1.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _FinishPicker(
              label: 'Rear shell',
              icon: CupertinoIcons.rectangle_on_rectangle,
              value: _rearShell,
              swatches: _swatches,
              onChanged: (value) => setState(() => _rearShell = value),
            ),
            const SizedBox(height: 15),
            _FinishPicker(
              label: 'Cardstock bezel',
              icon: Icons.border_outer,
              value: _cardstock,
              swatches: _swatches,
              onChanged: (value) => setState(() => _cardstock = value),
            ),
            const SizedBox(height: 15),
            _FinishPicker(
              label: 'Front shell',
              icon: CupertinoIcons.rectangle,
              value: _bezel,
              swatches: _swatches,
              onChanged: (value) => setState(() => _bezel = value),
            ),
            const SizedBox(height: 15),
            _FinishPicker(
              label: 'Kickstand',
              icon: CupertinoIcons.tray,
              value: _kickstand,
              swatches: _swatches,
              onChanged: (value) => setState(() => _kickstand = value),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _SheetButton(
                    label: 'Cancel',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SheetButton(
                    label: 'Save',
                    prominent: true,
                    onTap: _save,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FinishPicker extends StatelessWidget {
  const _FinishPicker({
    required this.label,
    required this.icon,
    required this.value,
    required this.swatches,
    required this.onChanged,
  });
  final String label;
  final IconData icon;
  final Color value;
  final List<Color> swatches;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xFFD1D1D6), size: 17),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: swatches
                .map(
                  (color) => Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _ColorSwatch(
                      color: color,
                      selected: color.toARGB32() == value.toARGB32(),
                      onTap: () => onChanged(color),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 34,
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? const Color(0xFF9D91FF) : Colors.transparent,
          width: 2,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
      ),
    ),
  );
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.onTap,
    this.prominent = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool prominent;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: prominent ? const Color(0xFF7C6CF8) : const Color(0xFF292929),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _DeviceModelThumbnail extends StatelessWidget {
  const _DeviceModelThumbnail({required this.controller});
  final ProductViewerController controller;
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Product3dViewer(
        controller: controller,
        showGestureHint: false,
        borderRadius: 18,
        yawOnly: true,
        allowZoom: false,
        allowPan: false,
        frameRate: 16,
      ),
    ),
  );
}

class _CardButton extends StatefulWidget {
  const _CardButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  State<_CardButton> createState() => _CardButtonState();
}

class _CardButtonState extends State<_CardButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onTap,
    onTapDown: (_) => setState(() => _pressed = true),
    onTapCancel: () => setState(() => _pressed = false),
    onTapUp: (_) => setState(() => _pressed = false),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 36,
      decoration: BoxDecoration(
        color: _pressed ? const Color(0xFF252525) : const Color(0xFF171717),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0x0FFFFFFF)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(widget.icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(
            widget.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class _AddDeviceCard extends StatelessWidget {
  const _AddDeviceCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Container(
    height: 96,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    decoration: BoxDecoration(
      color: const Color(0xFF121212),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0x0DFFFFFF)),
    ),
    child: Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0x33FFFFFF),
              style: BorderStyle.solid,
            ),
          ),
          child: const Icon(
            CupertinoIcons.bluetooth,
            color: Colors.white,
            size: 25,
          ),
        ),
        const SizedBox(width: 15),
        const Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add New Device',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Put your StickyPix device in pairing mode and keep it nearby.',
                maxLines: 2,
                style: TextStyle(
                  color: Color(0x99FFFFFF),
                  fontSize: 12,
                  height: 1.18,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _AddButton(onTap: onTap),
      ],
    ),
  );
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x0FFFFFFF)),
      ),
      child: const Row(
        children: [
          Icon(CupertinoIcons.add, color: Colors.white, size: 17),
          SizedBox(width: 6),
          Text(
            'Add Device',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class _DevicesNavigation extends StatelessWidget {
  const _DevicesNavigation({required this.onHome, required this.onUnavailable});

  final VoidCallback onHome;
  final ValueChanged<String> onUnavailable;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 20,
      right: 20,
      bottom: 18,
      child: SafeArea(
        top: false,
        child: Container(
          height: 74,
          decoration: BoxDecoration(
            color: const Color(0xF2111111),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0x0FFFFFFF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 26,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              _NavItem(
                icon: CupertinoIcons.person,
                label: 'Me',
                onTap: () => onUnavailable('Me'),
              ),
              _NavItem(
                icon: CupertinoIcons.photo_on_rectangle,
                label: 'Library',
                onTap: () => onUnavailable('Library'),
              ),
              _NavItem(
                icon: CupertinoIcons.house_fill,
                label: 'Home',
                onTap: onHome,
              ),
              _NavItem(
                icon: Icons.forum_outlined,
                label: 'Messages',
                onTap: () => onUnavailable('Messages'),
              ),
              const _NavItem(
                icon: CupertinoIcons.dot_radiowaves_left_right,
                label: 'Devices',
                selected: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : const Color(0xFF9B9BA1);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          height: 74,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: selected ? 22 : 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 3),
              AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: Container(
                  width: 18,
                  height: 3,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C6CF8),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
