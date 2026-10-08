import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/l10n/translations.dart';
import '../core/theme/app_theme.dart';
import '../models/proxy_node.dart';

class ConfigFormTabs extends StatefulWidget {
  final ProxyNode? initialNode;
  final String locale;

  const ConfigFormTabs({
    super.key,
    this.initialNode,
    required this.locale,
  });

  @override
  ConfigFormTabsState createState() => ConfigFormTabsState();
}

class ConfigFormTabsState extends State<ConfigFormTabs> with SingleTickerProviderStateMixin {
  late TabController tabController;

  // Tab 1: Basic Info
  late TextEditingController nameController;
  late TextEditingController addressController;
  late TextEditingController portController;

  // Tab 2: Encryption
  late TextEditingController uuidController;
  String? selectedFlow;
  late TextEditingController cipherController;
  late bool enableMux;

  // Tab 3: Transport
  late ProtocolType selectedProtocol;
  late NetworkType selectedNetwork;
  late TextEditingController pathController;
  late TextEditingController hostController;
  late TextEditingController serviceNameController;
  late bool grpcMultiMode;
  String? selectedHeaderType;
  String? selectedXhttpMode;
  late TextEditingController xhttpExtraController;

  // Tab 4: TLS
  late SecurityType selectedSecurity;
  late TextEditingController sniController;
  String? selectedFingerprint;
  late TextEditingController alpnController;
  late bool allowInsecure;
  late TextEditingController echConfigListController;
  late TextEditingController verifyPeerCertByNameController;
  late TextEditingController certificatePinningController;
  late TextEditingController publicKeyController;
  late TextEditingController shortIdController;
  late TextEditingController spiderXController;

  static const List<String> availableFlows = [
    '',
    'xtls-rprx-vision',
    'xtls-rprx-vision-udp443',
  ];

  static const List<String> availableCiphers = [
    'auto',
    'none',
    'zero',
    'aes-128-gcm',
    'aes-256-gcm',
    'chacha20-poly1305',
    '2022-blake3-aes-128-gcm',
    '2022-blake3-aes-256-gcm',
    '2022-blake3-chacha20-poly1305',
  ];

  static const List<String> availableFingerprints = [
    'chrome',
    'firefox',
    'safari',
    'ios',
    'android',
    'edge',
    '360',
    'qq',
    'random',
    'randomized',
  ];

  static const List<String> availableXhttpModes = [
    'auto',
    'packet-up',
    'stream-up',
    'stream-one',
  ];

  static const List<String> availableHeaderTypes = [
    'none',
    'http',
  ];

  @override
  void initState() {
    super.initState();
    tabController = TabController(length: 4, vsync: this);

    final n = widget.initialNode;

    // Tab 1: Basic Info
    nameController = TextEditingController(text: n?.name ?? 'Custom Node');
    addressController = TextEditingController(text: n?.address ?? '');
    portController = TextEditingController(text: (n?.port ?? 443).toString());

    // Tab 2: Encryption
    uuidController = TextEditingController(text: n?.uuidOrPassword ?? const Uuid().v4());
    selectedFlow = n?.flow ?? '';
    cipherController = TextEditingController(text: n?.cipher ?? 'auto');
    enableMux = n?.enableMux ?? false;

    // Tab 3: Transport
    selectedProtocol = n?.protocol ?? ProtocolType.vless;
    selectedNetwork = n?.network ?? NetworkType.tcp;
    pathController = TextEditingController(text: n?.path ?? '');
    hostController = TextEditingController(text: n?.host ?? '');
    serviceNameController = TextEditingController(text: n?.serviceName ?? '');
    grpcMultiMode = true;
    selectedHeaderType = (n?.headerType != null && n!.headerType!.isNotEmpty) ? n.headerType! : 'none';
    selectedXhttpMode = (n?.mode != null && n!.mode!.isNotEmpty) ? n.mode! : 'auto';
    xhttpExtraController = TextEditingController(text: n?.extra ?? '');

    // Tab 4: TLS
    selectedSecurity = n?.security ?? SecurityType.tls;
    sniController = TextEditingController(text: n?.sni ?? '');
    selectedFingerprint = (n?.fingerprint != null && n!.fingerprint!.isNotEmpty) ? n.fingerprint! : 'chrome';
    alpnController = TextEditingController(text: (n?.alpn != null) ? n!.alpn!.join(',') : 'h2,http/1.1');
    allowInsecure = n?.allowInsecure ?? false;
    echConfigListController = TextEditingController(text: n?.echConfigList ?? '');
    verifyPeerCertByNameController = TextEditingController(text: n?.verifyPeerCertByName ?? '');
    certificatePinningController = TextEditingController(text: n?.certificatePinning ?? '');
    publicKeyController = TextEditingController(text: n?.publicKey ?? '');
    shortIdController = TextEditingController(text: n?.shortId ?? '');
    spiderXController = TextEditingController(text: n?.spiderX ?? '/');
  }

  @override
  void dispose() {
    tabController.dispose();
    nameController.dispose();
    addressController.dispose();
    portController.dispose();
    uuidController.dispose();
    cipherController.dispose();
    pathController.dispose();
    hostController.dispose();
    serviceNameController.dispose();
    xhttpExtraController.dispose();
    sniController.dispose();
    alpnController.dispose();
    echConfigListController.dispose();
    verifyPeerCertByNameController.dispose();
    certificatePinningController.dispose();
    publicKeyController.dispose();
    shortIdController.dispose();
    spiderXController.dispose();
    super.dispose();
  }

  String? validate() {
    if (addressController.text.trim().isEmpty) {
      return AppStrings.get('server_address', locale: widget.locale) + ' is required';
    }
    final p = int.tryParse(portController.text.trim());
    if (p == null || p <= 0 || p > 65535) {
      return 'Port must be a valid number between 1 and 65535';
    }
    if (uuidController.text.trim().isEmpty) {
      return AppStrings.get('uuid_password', locale: widget.locale) + ' is required';
    }
    if (selectedSecurity == SecurityType.reality && publicKeyController.text.trim().isEmpty) {
      return 'Reality Public Key (pbk) is required for Reality mode';
    }
    return null;
  }

  ProxyNode buildNode({String? id, bool isActive = false}) {
    final original = widget.initialNode;
    final port = int.tryParse(portController.text.trim()) ?? 443;
    final addr = addressController.text.trim();
    final name = nameController.text.trim().isEmpty ? 'Node-$addr' : nameController.text.trim();

    final alpnRaw = alpnController.text.trim();
    final alpnList = alpnRaw.isNotEmpty
        ? alpnRaw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
        : null;

    final flowVal = (selectedFlow != null && selectedFlow!.trim().isNotEmpty) ? selectedFlow!.trim() : null;
    final headerTypeVal = (selectedHeaderType != null && selectedHeaderType != 'none') ? selectedHeaderType : null;
    final xhttpModeVal = (selectedXhttpMode != null && selectedXhttpMode != 'auto') ? selectedXhttpMode : null;

    return ProxyNode(
      id: id ?? original?.id ?? const Uuid().v4(),
      name: name,
      protocol: selectedProtocol,
      address: addr,
      port: port,
      uuidOrPassword: uuidController.text.trim(),
      alterId: original?.alterId ?? 0,
      cipher: cipherController.text.trim().isEmpty ? null : cipherController.text.trim(),
      network: selectedNetwork,
      path: pathController.text.trim().isEmpty ? null : pathController.text.trim(),
      host: hostController.text.trim().isEmpty ? null : hostController.text.trim(),
      serviceName: serviceNameController.text.trim().isEmpty ? null : serviceNameController.text.trim(),
      security: selectedSecurity,
      sni: sniController.text.trim().isEmpty ? null : sniController.text.trim(),
      alpn: alpnList,
      allowInsecure: allowInsecure,
      fingerprint: (selectedFingerprint != null && selectedFingerprint!.isNotEmpty) ? selectedFingerprint : null,
      publicKey: publicKeyController.text.trim().isEmpty ? null : publicKeyController.text.trim(),
      shortId: shortIdController.text.trim().isEmpty ? null : shortIdController.text.trim(),
      spiderX: spiderXController.text.trim().isEmpty ? null : spiderXController.text.trim(),
      mode: xhttpModeVal,
      extra: xhttpExtraController.text.trim().isEmpty ? null : xhttpExtraController.text.trim(),
      flow: flowVal,
      headerType: headerTypeVal,
      enableMux: enableMux,
      echConfigList: echConfigListController.text.trim().isEmpty ? null : echConfigListController.text.trim(),
      verifyPeerCertByName: verifyPeerCertByNameController.text.trim().isEmpty ? null : verifyPeerCertByNameController.text.trim(),
      certificatePinning: certificatePinningController.text.trim().isEmpty ? null : certificatePinningController.text.trim(),
      subscriptionId: original?.subscriptionId,
      latencyMs: original?.latencyMs,
      lastTestedAt: original?.lastTestedAt,
      isActive: isActive || (original?.isActive ?? false),
      originalAddress: original?.originalAddress,
      countryCode: original?.countryCode,
      country: original?.country,
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.locale;

    return SizedBox(
      width: 580,
      height: 490,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: TabBar(
              controller: tabController,
              labelColor: AppTheme.primaryAccent,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppTheme.primaryAccent,
              indicatorSize: TabBarIndicatorSize.tab,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
              tabs: [
                Tab(
                  icon: const Icon(Icons.info_outline_rounded, size: 18),
                  text: AppStrings.get('tab_basic_info', locale: loc),
                ),
                Tab(
                  icon: const Icon(Icons.lock_outline_rounded, size: 18),
                  text: AppStrings.get('tab_encryption', locale: loc),
                ),
                Tab(
                  icon: const Icon(Icons.swap_calls_rounded, size: 18),
                  text: AppStrings.get('tab_transport', locale: loc),
                ),
                Tab(
                  icon: const Icon(Icons.security_rounded, size: 18),
                  text: AppStrings.get('tab_tls', locale: loc),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              controller: tabController,
              children: [
                _buildBasicInfoTab(loc),
                _buildEncryptionTab(loc),
                _buildTransportTab(loc),
                _buildTlsTab(loc),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInfoTab(String loc) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: nameController,
            decoration: InputDecoration(
              labelText: AppStrings.get('alias_remark', locale: loc),
              hintText: 'e.g. My Fast VPS',
              prefixIcon: const Icon(Icons.label_rounded, size: 20),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: addressController,
            decoration: InputDecoration(
              labelText: AppStrings.get('server_address', locale: loc),
              hintText: '198.51.100.1 or mydomain.com',
              prefixIcon: const Icon(Icons.dns_rounded, size: 20),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: portController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: AppStrings.get('server_port', locale: loc),
              hintText: '443',
              prefixIcon: const Icon(Icons.tag_rounded, size: 20),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEncryptionTab(String loc) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: uuidController,
            decoration: InputDecoration(
              labelText: AppStrings.get('uuid_password', locale: loc),
              prefixIcon: const Icon(Icons.key_rounded, size: 20),
              suffixIcon: IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                tooltip: 'Generate Random UUID',
                onPressed: () {
                  setState(() {
                    uuidController.text = const Uuid().v4();
                  });
                },
              ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: (selectedFlow != null && availableFlows.contains(selectedFlow)) ? selectedFlow : '',
            decoration: InputDecoration(
              labelText: AppStrings.get('flow', locale: loc),
              prefixIcon: const Icon(Icons.waves_rounded, size: 20),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: '', child: Text('None / Empty')),
              DropdownMenuItem(value: 'xtls-rprx-vision', child: Text('xtls-rprx-vision (Vision)')),
              DropdownMenuItem(value: 'xtls-rprx-vision-udp443', child: Text('xtls-rprx-vision-udp443')),
            ],
            onChanged: (val) {
              setState(() => selectedFlow = val);
            },
          ),
          const SizedBox(height: 16),
          Autocomplete<String>(
            initialValue: TextEditingValue(text: cipherController.text),
            optionsBuilder: (textVal) {
              if (textVal.text.isEmpty) return availableCiphers;
              return availableCiphers.where((c) => c.toLowerCase().contains(textVal.text.toLowerCase()));
            },
            onSelected: (val) {
              cipherController.text = val;
            },
            fieldViewBuilder: (ctx, controller, focusNode, onFieldSubmitted) {
              controller.addListener(() {
                cipherController.text = controller.text;
              });
              return TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: InputDecoration(
                  labelText: AppStrings.get('cipher_encryption', locale: loc),
                  prefixIcon: const Icon(Icons.lock_clock_rounded, size: 20),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            secondary: const Icon(Icons.merge_type_rounded, color: AppTheme.primaryAccent),
            title: Text(
              AppStrings.get('enable_mux', locale: loc),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              AppStrings.get('enable_mux_desc', locale: loc),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
            ),
            value: enableMux,
            onChanged: (val) => setState(() => enableMux = val),
          ),
        ],
      ),
    );
  }

  Widget _buildTransportTab(String loc) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<ProtocolType>(
                  value: selectedProtocol,
                  decoration: InputDecoration(
                    labelText: AppStrings.get('protocol', locale: loc),
                    prefixIcon: const Icon(Icons.layers_rounded, size: 20),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: ProtocolType.values
                      .map((p) => DropdownMenuItem(
                            value: p,
                            child: Text(p.name.toUpperCase()),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => selectedProtocol = val);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<NetworkType>(
                  value: selectedNetwork,
                  decoration: InputDecoration(
                    labelText: AppStrings.get('transport_network', locale: loc),
                    prefixIcon: const Icon(Icons.router_rounded, size: 20),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: NetworkType.values
                      .map((n) => DropdownMenuItem(
                            value: n,
                            child: Text(n.name.toUpperCase()),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => selectedNetwork = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Dynamic Transport Fields based on NetworkType:
          if (selectedNetwork == NetworkType.ws || selectedNetwork == NetworkType.httpUpgrade || selectedNetwork == NetworkType.h2) ...[
            TextField(
              controller: pathController,
              decoration: const InputDecoration(
                labelText: 'Path (e.g. / or /ws)',
                prefixIcon: Icon(Icons.alt_route_rounded, size: 20),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: hostController,
              decoration: const InputDecoration(
                labelText: 'Host header (e.g. cdn.example.com)',
                prefixIcon: Icon(Icons.language_rounded, size: 20),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ] else if (selectedNetwork == NetworkType.grpc) ...[
            TextField(
              controller: serviceNameController,
              decoration: InputDecoration(
                labelText: AppStrings.get('service_name', locale: loc),
                hintText: 'e.g. v2ray-grpc',
                prefixIcon: const Icon(Icons.cloud_sync_rounded, size: 20),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(AppStrings.get('multi_mode', locale: loc)),
              value: grpcMultiMode,
              onChanged: (val) => setState(() => grpcMultiMode = val),
            ),
          ] else if (selectedNetwork == NetworkType.xhttp || selectedNetwork == NetworkType.splithttp) ...[
            TextField(
              controller: pathController,
              decoration: const InputDecoration(
                labelText: 'Path (e.g. /xhttp)',
                prefixIcon: Icon(Icons.alt_route_rounded, size: 20),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: hostController,
              decoration: const InputDecoration(
                labelText: 'Host header',
                prefixIcon: Icon(Icons.language_rounded, size: 20),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: selectedXhttpMode,
              decoration: InputDecoration(
                labelText: AppStrings.get('xhttp_mode', locale: loc),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: availableXhttpModes
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (val) => setState(() => selectedXhttpMode = val),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: xhttpExtraController,
              decoration: InputDecoration(
                labelText: AppStrings.get('xhttp_extra', locale: loc),
                hintText: '{"noSSEHeader": false}',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ] else if (selectedNetwork == NetworkType.tcp) ...[
            DropdownButtonFormField<String>(
              value: selectedHeaderType,
              decoration: InputDecoration(
                labelText: AppStrings.get('header_type', locale: loc),
                prefixIcon: const Icon(Icons.code_rounded, size: 20),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: availableHeaderTypes
                  .map((h) => DropdownMenuItem(value: h, child: Text(h.toUpperCase())))
                  .toList(),
              onChanged: (val) => setState(() => selectedHeaderType = val),
            ),
            if (selectedHeaderType == 'http') ...[
              const SizedBox(height: 12),
              TextField(
                controller: pathController,
                decoration: const InputDecoration(
                  labelText: 'HTTP Request Path (e.g. /)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: hostController,
                decoration: const InputDecoration(
                  labelText: 'HTTP Host Header',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildTlsTab(String loc) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<SecurityType>(
            value: selectedSecurity,
            decoration: InputDecoration(
              labelText: AppStrings.get('tls_mode', locale: loc),
              prefixIcon: const Icon(Icons.shield_outlined, size: 20),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: SecurityType.values
                .map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(s.name.toUpperCase()),
                    ))
                .toList(),
            onChanged: (val) {
              if (val != null) setState(() => selectedSecurity = val);
            },
          ),
          const SizedBox(height: 16),

          if (selectedSecurity == SecurityType.none)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: Colors.amber),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppStrings.get('tls_none_hint', locale: loc),
                      style: const TextStyle(fontSize: 12, color: Colors.amber),
                    ),
                  ),
                ],
              ),
            ),

          if (selectedSecurity == SecurityType.tls) ...[
            TextField(
              controller: sniController,
              decoration: InputDecoration(
                labelText: AppStrings.get('sni_servername', locale: loc),
                hintText: 'e.g. example.com',
                prefixIcon: const Icon(Icons.link_rounded, size: 20),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: availableFingerprints.contains(selectedFingerprint) ? selectedFingerprint : 'chrome',
                    decoration: InputDecoration(
                      labelText: AppStrings.get('fingerprint', locale: loc),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: availableFingerprints
                        .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                        .toList(),
                    onChanged: (val) => setState(() => selectedFingerprint = val),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: alpnController,
                    decoration: InputDecoration(
                      labelText: AppStrings.get('alpn', locale: loc),
                      hintText: 'h2,http/1.1',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                AppStrings.get('allow_insecure', locale: loc),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                AppStrings.get('allow_insecure_desc', locale: loc),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
              ),
              value: allowInsecure,
              onChanged: (val) => setState(() => allowInsecure = val),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: echConfigListController,
              decoration: InputDecoration(
                labelText: AppStrings.get('ech_config_list', locale: loc),
                hintText: 'Base64 encoded ECH configs',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: verifyPeerCertByNameController,
              decoration: InputDecoration(
                labelText: AppStrings.get('verify_peer_cert', locale: loc),
                hintText: 'Expected certificate subject name',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: certificatePinningController,
              decoration: InputDecoration(
                labelText: AppStrings.get('cert_pinning', locale: loc),
                hintText: 'SHA-256 public key hash',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],

          if (selectedSecurity == SecurityType.reality) ...[
            TextField(
              controller: sniController,
              decoration: InputDecoration(
                labelText: AppStrings.get('sni_servername', locale: loc),
                hintText: 'e.g. play.google.com, yahoo.com',
                prefixIcon: const Icon(Icons.link_rounded, size: 20),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: availableFingerprints.contains(selectedFingerprint) ? selectedFingerprint : 'chrome',
                    decoration: InputDecoration(
                      labelText: AppStrings.get('fingerprint', locale: loc),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: availableFingerprints
                        .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                        .toList(),
                    onChanged: (val) => setState(() => selectedFingerprint = val),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: spiderXController,
                    decoration: InputDecoration(
                      labelText: AppStrings.get('spider_x', locale: loc),
                      hintText: '/',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: publicKeyController,
              decoration: InputDecoration(
                labelText: AppStrings.get('public_key', locale: loc),
                hintText: 'Reality Public Key (pbk)',
                prefixIcon: const Icon(Icons.vpn_key_rounded, size: 20),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: shortIdController,
              decoration: InputDecoration(
                labelText: AppStrings.get('short_id', locale: loc),
                hintText: 'Reality Short ID (sid)',
                prefixIcon: const Icon(Icons.fingerprint_rounded, size: 20),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
