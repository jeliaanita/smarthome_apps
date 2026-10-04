// Widget bersama untuk pola "ringkasan → klik → detail" (QC 09).
// Taruh di: lib/core/widgets/ac_unit_widgets.dart
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mobile/core/theme/app_colors.dart';
import 'package:mobile/core/controllers/openhab_controller.dart';
import 'package:mobile/core/models/openhab_item.dart';

bool _hasValue(String? s) =>
    s != null && s.isNotEmpty && s.toUpperCase() != 'NULL' && s.toUpperCase() != 'UNDEF';

Color _fg(bool isDark) => isDark ? Colors.white.withValues(alpha: 0.85) : const Color(0xCC18181B);
Color _muted(bool isDark) => isDark ? Colors.white60 : const Color(0xFF71717A);
Color _surface(bool isDark) => isDark ? const Color(0xFF27272A) : Colors.white;

// ─────────────────────────────────────────────────────────────────────
// Shell sheet detail + Informasi teknis
// ─────────────────────────────────────────────────────────────────────

class DetailSheetShell extends StatelessWidget {
  final ScrollController scrollController;
  final String title;
  final String subtitle;
  final List<Widget> children;
  const DetailSheetShell({
    super.key,
    required this.scrollController,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF18181B) : const Color(0xFFF5F5F7),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF3F3F46) : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 20,
                        color: isDark ? Colors.white : const Color(0xFF18181B))),
                Text(subtitle,
                    style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: _muted(isDark))),
              ]),
            ),
            IconButton(
              icon: Icon(Icons.close, color: isDark ? Colors.white70 : Colors.black54),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class TechInfoSection extends StatelessWidget {
  final List<OpenHABItem> items;
  const TechInfoSection({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = _muted(isDark);
    return Material(
        color: _surface(isDark),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          leading: FaIcon(FontAwesomeIcons.screwdriverWrench, size: 14, color: muted),
          title: Text('Informasi teknis',
              style: TextStyle(
                  fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14,
                  color: _fg(isDark))),
          children: [
            for (final i in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    flex: 5,
                    child: Text('${i.name}\n${i.type}',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: muted)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: Text(i.state ?? '-',
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: muted)),
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Ringkasan perangkat (Equipment) + baris fungsi + section
// ─────────────────────────────────────────────────────────────────────

class EquipmentSummaryCard extends StatelessWidget {
  final String name;
  final List<OpenHABItem> items;
  final FaIconData icon;
  final bool Function(OpenHABItem) isActive;
  final void Function(OpenHABItem) onToggle;
  final VoidCallback onOpen;

  const EquipmentSummaryCard({
    super.key,
    required this.name,
    required this.items,
    required this.icon,
    required this.isActive,
    required this.onToggle,
    required this.onOpen,
  });

  OpenHABItem? get _primarySwitch {
    final switches = items.where((i) => i.isSwitch).toList();
    if (switches.isEmpty) return null;
    return switches.firstWhere(
      (i) => i.label.toLowerCase().contains('power'),
      orElse: () => switches.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = _primarySwitch;
    final activeCount = items.where(isActive).length;
    final on = primary != null ? primary.isOn : activeCount > 0;

    final fg = on ? Colors.white : (isDark ? Colors.white.withValues(alpha: 0.8) : const Color(0xCC18181B));
    final muted = on ? Colors.white70 : _muted(isDark);
    final pillBg = on
        ? Colors.white.withValues(alpha: 0.25)
        : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0x33787878));

    return GestureDetector(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
        decoration: BoxDecoration(
          color: on ? AppColors.primary : _surface(isDark),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
                blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Padding(padding: const EdgeInsets.only(top: 6), child: FaIcon(icon, size: 22, color: fg)),
            if (primary != null)
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: primary.isOn,
                  onChanged: (_) => onToggle(primary),
                  activeThumbColor: Colors.white,
                  activeTrackColor: Colors.white38,
                ),
              ),
          ]),
          const Spacer(),
          Text(name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, color: fg)),
          const SizedBox(height: 2),
          Text('${items.length} fungsi · $activeCount aktif',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: muted)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: pillBg, borderRadius: BorderRadius.circular(26)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              FaIcon(FontAwesomeIcons.chevronRight, size: 8, color: fg),
              const SizedBox(width: 4),
              Text('Lihat detail', style: TextStyle(fontFamily: 'Inter', fontSize: 8, color: fg)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class CompactItemRow extends StatelessWidget {
  final OpenHABItem item;
  final FaIconData icon;
  final bool active;
  final String stateLabel;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  const CompactItemRow({
    super.key,
    required this.item,
    required this.icon,
    required this.active,
    required this.stateLabel,
    required this.onTap,
    required this.onToggle,
  });

  bool get _tappable =>
      item.isSwitch || item.isDimmer || item.isColor || item.type == 'Player' ||
      item.isRollershutter || item.isString || item.isCamera || item.isImage;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = _muted(isDark);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _tappable ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: active
                  ? AppColors.primary
                  : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5)),
              shape: BoxShape.circle,
            ),
            child: Center(child: FaIcon(icon, size: 13, color: active ? Colors.white : muted)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: 'Inter', fontWeight: FontWeight.w500, fontSize: 14, color: _fg(isDark))),
          ),
          if (item.isSwitch)
            Transform.scale(
              scale: 0.8,
              child: Switch(
                value: item.isOn,
                onChanged: (_) => onToggle(),
                activeThumbColor: AppColors.primary,
              ),
            )
          else ...[
            Text(stateLabel, style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: muted)),
            if (_tappable) ...[
              const SizedBox(width: 6),
              FaIcon(FontAwesomeIcons.chevronRight, size: 10, color: muted),
            ],
          ],
        ]),
      ),
    );
  }
}

/// "Kontrol utama" selalu terbuka; switch alarm/deteksi dilipat.
List<Widget> buildEquipmentSections(
  BuildContext context,
  List<OpenHABItem> items,
  Widget Function(OpenHABItem) rowBuilder,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  bool isAlarm(OpenHABItem i) {
    final l = i.label.toLowerCase();
    return i.isSwitch && (l.contains('alarm') || l.contains('motion') || l.contains('detect'));
  }

  final main = items.where((i) => !isAlarm(i)).toList();
  final alarms = items.where(isAlarm).toList();

  Widget rowsOf(List<OpenHABItem> list) => Container(
        decoration: BoxDecoration(color: _surface(isDark), borderRadius: BorderRadius.circular(20)),
        child: Column(children: [
          for (var i = 0; i < list.length; i++) ...[
            rowBuilder(list[i]),
            if (i < list.length - 1)
              Divider(height: 1, indent: 60, color: isDark ? Colors.white10 : Colors.black12),
          ],
        ]),
      );

  return [
    if (main.isNotEmpty) ...[
      Text('Kontrol utama',
          style: TextStyle(
              fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: _muted(isDark))),
      const SizedBox(height: 8),
      rowsOf(main),
    ],
    if (alarms.isNotEmpty) ...[
      const SizedBox(height: 16),
      Material(
        color: _surface(isDark),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            title: Text(
                'Alarm & deteksi (${alarms.where((i) => i.isOn).length}/${alarms.length} aktif)',
                style: TextStyle(
                    fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, color: _fg(isDark))),
            children: [rowsOf(alarms)],
          ),
        ),
      ),
    ],
  ];
}

// ─────────────────────────────────────────────────────────────────────
// AC: kartu ringkas + halaman detail (power, mode, setpoint, suhu, fan)
// ─────────────────────────────────────────────────────────────────────

class AcUnitSummaryCard extends StatelessWidget {
  final OHAcUnit unit;
  final OpenHABController ctrl;
  const AcUnitSummaryCard({super.key, required this.unit, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOn = ctrl.getItem(unit.powerItem)?.isOn ?? false;
    final setTemp = unit.setTempItem != null ? ctrl.getItem(unit.setTempItem!)?.numericValue : null;
    final roomTemp = unit.roomTempItem != null ? ctrl.getItem(unit.roomTempItem!)?.numericValue : null;
    final modeText = unit.stateModeItem != null ? ctrl.getItem(unit.stateModeItem!)?.state : null;

    final parts = <String>[
      if (roomTemp != null) 'Ruang ${roomTemp.toStringAsFixed(1)}°C',
      if (_hasValue(modeText)) modeText!,
    ];
    final fg = isOn ? Colors.white : (isDark ? Colors.white.withValues(alpha: 0.8) : const Color(0xCC18181B));
    final muted = isOn ? Colors.white70 : _muted(isDark);

    return GestureDetector(
      onTap: () => showAcDetailSheet(context, ctrl, unit),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: isOn ? AppColors.primary : _surface(isDark),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
                blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(children: [
          FaIcon(FontAwesomeIcons.wind, size: 22, color: fg),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(unit.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 15, color: fg)),
              const SizedBox(height: 2),
              Text(parts.isEmpty ? 'Air Conditioner' : parts.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: muted)),
            ]),
          ),
          if (setTemp != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text('${setTemp.toInt()}°',
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 26, color: fg)),
            ),
          Switch(
            value: isOn,
            onChanged: (v) => ctrl.sendCommand(unit.powerItem, v ? 'ON' : 'OFF'),
            activeThumbColor: Colors.white,
            activeTrackColor: Colors.white38,
          ),
          FaIcon(FontAwesomeIcons.chevronRight, size: 12, color: muted),
        ]),
      ),
    );
  }
}

void showAcDetailSheet(BuildContext context, OpenHABController ctrl, OHAcUnit unit) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, sc) => ListenableBuilder(
        listenable: ctrl,
        builder: (ctx, __) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final isOn = ctrl.getItem(unit.powerItem)?.isOn ?? false;

          final setTempItem = unit.setTempItem;
          final currentTemp =
              (setTempItem != null ? ctrl.getItem(setTempItem)?.numericValue : null) ?? 24;
          void changeTemp(double d) {
            if (setTempItem == null) return;
            ctrl.setTemperature(setTempItem, (currentTemp + d).clamp(16.0, 30.0));
          }

          final roomTemp = unit.roomTempItem != null ? ctrl.getItem(unit.roomTempItem!)?.numericValue : null;
          final humidity =
              unit.roomHumidityItem != null ? ctrl.getItem(unit.roomHumidityItem!)?.numericValue : null;
          final status = unit.statusItem != null ? ctrl.getItem(unit.statusItem!)?.state : null;

          final tech = <String?>[
            unit.powerItem, unit.modeItem, unit.fanItem, unit.setTempItem,
            unit.roomTempItem, unit.roomHumidityItem, unit.statusItem,
            unit.stateModeItem, unit.stateFanItem,
          ].whereType<String>().map(ctrl.getItem).whereType<OpenHABItem>().toList();

          Widget circleBtn(IconData i, VoidCallback? onTap) => GestureDetector(
                onTap: onTap,
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF3F3F46) : Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(i, size: 22, color: _fg(isDark)),
                ),
              );

          Widget chip(FaIconData i, String t, {Color? c}) => Row(mainAxisSize: MainAxisSize.min, children: [
                FaIcon(i, size: 12, color: c ?? _muted(isDark)),
                const SizedBox(width: 4),
                Text(t, style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: c ?? _muted(isDark))),
              ]);

          return DetailSheetShell(
            scrollController: sc,
            title: unit.label,
            subtitle: 'Air Conditioner',
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: _surface(isDark), borderRadius: BorderRadius.circular(24)),
                child: Column(children: [
                  Row(children: [
                    Text('Power',
                        style: TextStyle(
                            fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 15, color: _fg(isDark))),
                    const Spacer(),
                    Switch(
                      value: isOn,
                      onChanged: (v) => ctrl.sendCommand(unit.powerItem, v ? 'ON' : 'OFF'),
                      activeThumbColor: AppColors.primary,
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    circleBtn(Icons.remove, setTempItem == null ? null : () => changeTemp(-1)),
                    const SizedBox(width: 24),
                    Column(children: [
                      Text('${currentTemp.toInt()}°',
                          style: TextStyle(
                              fontFamily: 'Inter', fontSize: 56, fontWeight: FontWeight.w600,
                              height: 1, color: _fg(isDark))),
                      Text('Setpoint · Celsius',
                          style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: _muted(isDark))),
                    ]),
                    const SizedBox(width: 24),
                    circleBtn(Icons.add, setTempItem == null ? null : () => changeTemp(1)),
                  ]),
                  if (roomTemp != null || humidity != null || _hasValue(status)) ...[
                    const SizedBox(height: 16),
                    Wrap(alignment: WrapAlignment.center, spacing: 14, runSpacing: 4, children: [
                      if (roomTemp != null)
                        chip(FontAwesomeIcons.temperatureHalf, 'Suhu ruang ${roomTemp.toStringAsFixed(1)}°C'),
                      if (humidity != null)
                        chip(FontAwesomeIcons.droplet, '${humidity.toStringAsFixed(0)}%'),
                      if (_hasValue(status))
                        chip(
                          status!.toLowerCase() == 'online'
                              ? FontAwesomeIcons.circleCheck
                              : FontAwesomeIcons.circleExclamation,
                          status,
                          c: status.toLowerCase() == 'online' ? Colors.green : Colors.redAccent,
                        ),
                    ]),
                  ],
                  if (unit.modeItem != null) ...[
                    const SizedBox(height: 16),
                    _cycleSelector(ctx, ctrl, FontAwesomeIcons.wind, 'Mode',
                        unit.modeItem!, unit.stateModeItem, 1, 5),
                  ],
                  if (unit.fanItem != null) ...[
                    const SizedBox(height: 10),
                    _cycleSelector(ctx, ctrl, FontAwesomeIcons.fan, 'Fan',
                        unit.fanItem!, unit.stateFanItem, 1, 4),
                  ],
                ]),
              ),
              const SizedBox(height: 16),
              TechInfoSection(items: tech),
            ],
          );
        },
      ),
    ),
  );
}

Widget _cycleSelector(BuildContext context, OpenHABController ctrl, FaIconData icon, String label,
    String commandItem, String? stateItem, int min, int max) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final cur = ctrl.getItem(commandItem)?.numericValue?.round() ?? min;
  final stateText = stateItem != null ? ctrl.getItem(stateItem)?.state : null;
  final text = _hasValue(stateText) ? stateText! : '$label $cur';

  void cycle(int d) {
    var n = cur + d;
    if (n > max) n = min;
    if (n < min) n = max;
    ctrl.sendCommand(commandItem, n.toString());
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3F3F46) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(49)),
    child: Row(children: [
      GestureDetector(
        onTap: () => cycle(-1),
        child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.chevron_left, size: 20)),
      ),
      Expanded(
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          FaIcon(icon, size: 14, color: _muted(isDark)),
          const SizedBox(width: 8),
          Text(text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: _fg(isDark))),
        ]),
      ),
      GestureDetector(
        onTap: () => cycle(1),
        child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.chevron_right, size: 20)),
      ),
    ]),
  );
}