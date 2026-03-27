
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:stock_fabric/services/supabase_func.dart';

enum ResultViewMode { pending, history }

class _LocatorGroup {
  const _LocatorGroup({
    required this.locator,
    required this.rows,
  });

  final String locator;
  final List<Map<String, dynamic>> rows;

  List<int> get ids =>
      rows.map((item) => item['id']).whereType<int>().toList(growable: false);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final supaFunc = SupabaseFunc();
  final _controllerSRN = TextEditingController();
  final DateFormat _displayDateFormat = DateFormat('dd/MM/yyyy');
  final DateFormat _queryDateFormat = DateFormat('yyyy-MM-dd');

  ResultViewMode _viewMode = ResultViewMode.pending;
  DateTime? _selectedPlanDate;
  bool _isLoading = false;
  String? _errorMessage;
  final Set<int> _selectedIds = <int>{};
  List<Map<String, dynamic>> data = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _controllerSRN.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await supaFunc.fetchSrn(
        searchText: _controllerSRN.text,
        planDate: _selectedPlanDate == null
            ? null
            : _queryDateFormat.format(_selectedPlanDate!),
        isConfirmed: _viewMode == ResultViewMode.history,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        data = result;
        _selectedIds.clear();
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Không tải được dữ liệu. Vui lòng thử lại.';
        data = [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickPlanDate() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedPlanDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );

    if (pickedDate == null) {
      return;
    }

    setState(() {
      _selectedPlanDate = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
      );
    });

    await _loadData();
  }

  Future<void> _resetFilters() async {
    _controllerSRN.clear();
    setState(() {
      _selectedPlanDate = null;
      _viewMode = ResultViewMode.pending;
      _selectedIds.clear();
    });
    await _loadData();
  }

  Future<void> _setViewMode(ResultViewMode mode) async {
    if (_viewMode == mode) {
      return;
    }

    setState(() {
      _viewMode = mode;
      _selectedIds.clear();
    });

    await _loadData();
  }

  String _formatDisplayDate(dynamic value) {
    if (value == null || value.toString().isEmpty) {
      return 'Chưa có';
    }

    final parsedDate = DateTime.tryParse(value.toString());
    if (parsedDate == null) {
      return value.toString();
    }

    return _displayDateFormat.format(parsedDate);
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String get _selectedDateLabel {
    if (_selectedPlanDate == null) {
      return 'Tất cả ngày';
    }
    return _displayDateFormat.format(_selectedPlanDate!);
  }

  bool get _isPendingMode => _viewMode == ResultViewMode.pending;

  bool get _isAllSelected =>
      data.isNotEmpty &&
      data.every((item) => _selectedIds.contains(_toInt(item['id'])));

  List<_LocatorGroup> get _groupedData {
    final grouped = <String, List<Map<String, dynamic>>>{};

    for (final item in data) {
      final locator = item['locator']?.toString() ?? '-';
      grouped.putIfAbsent(locator, () => <Map<String, dynamic>>[]).add(item);
    }

    final groups = grouped.entries
        .map(
          (entry) => _LocatorGroup(locator: entry.key, rows: entry.value),
        )
        .toList(growable: false);

    groups.sort((left, right) => _compareLocator(left.locator, right.locator));
    return groups;
  }

  String get _resultSummary {
    final docRefCount = data.map((item) => item['doc_ref']).toSet().length;
    return '${_groupedData.length} locator / $docRefCount SRN';
  }

  Widget _buildViewButton({
    required ResultViewMode mode,
    required String label,
  }) {
    final isSelected = _viewMode == mode;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => _setViewMode(mode),
    );
  }

  void _toggleSelectAll(bool? checked) {
    setState(() {
      if (checked ?? false) {
        _selectedIds
          ..clear()
          ..addAll(data.map((item) => _toInt(item['id'])));
      } else {
        _selectedIds.clear();
      }
    });
  }

  void _toggleGroupSelection(_LocatorGroup group, bool? checked) {
    setState(() {
      if (checked ?? false) {
        _selectedIds.addAll(group.ids);
      } else {
        _selectedIds.removeAll(group.ids);
      }
    });
  }

  String _extractSrnSuffix(String docRef) {
    final match = RegExp(r'(\d{4})$').firstMatch(docRef);
    if (match != null) {
      return match.group(1)!;
    }
    return docRef;
  }

  String _buildSrnLabel(_LocatorGroup group) {
    final suffixes = group.rows
        .map((item) => item['doc_ref']?.toString() ?? '')
        .where((value) => value.isNotEmpty)
        .map(_extractSrnSuffix)
        .toSet()
        .toList();

    suffixes.sort((left, right) {
      final leftNumber = int.tryParse(left);
      final rightNumber = int.tryParse(right);
      if (leftNumber != null && rightNumber != null) {
        return leftNumber.compareTo(rightNumber);
      }
      return left.compareTo(right);
    });

    return suffixes.join('/');
  }

  int _compareLocator(String left, String right) {
    final leftTokens = RegExp(r'[A-Za-z]+|\d+').allMatches(left).map((m) => m.group(0)!).toList();
    final rightTokens = RegExp(r'[A-Za-z]+|\d+').allMatches(right).map((m) => m.group(0)!).toList();
    final length = leftTokens.length < rightTokens.length ? leftTokens.length : rightTokens.length;

    for (var index = 0; index < length; index++) {
      final leftToken = leftTokens[index];
      final rightToken = rightTokens[index];
      final leftNumber = int.tryParse(leftToken);
      final rightNumber = int.tryParse(rightToken);

      if (leftNumber != null && rightNumber != null) {
        final compare = leftNumber.compareTo(rightNumber);
        if (compare != 0) {
          return compare;
        }
        continue;
      }

      final compare = leftToken.toUpperCase().compareTo(rightToken.toUpperCase());
      if (compare != 0) {
        return compare;
      }
    }

    return leftTokens.length.compareTo(rightTokens.length);
  }

  Future<void> _confirmSelected() async {
    if (!_isPendingMode || _selectedIds.isEmpty) {
      return;
    }

    final shouldConfirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xác nhận'),
        content: Text('Xác nhận ${_selectedIds.length} dòng đã chọn?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );

    if (shouldConfirm != true) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await supaFunc.confirmSrn(_selectedIds.toList());
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã xác nhận ${_selectedIds.length} dòng.')),
      );
      await _loadData();
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = 'Xác nhận thất bại. Vui lòng thử lại.';
      });
    }
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Expanded(
            flex: 5,
            child: Text(
              'Locator',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const Expanded(
            flex: 2,
            child: Text(
              'SRN',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text(
                  'Chọn',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                if (_isPendingMode)
                  Checkbox(
                    value: _isAllSelected,
                    onChanged: _toggleSelectAll,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('APP Fabric'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _controllerSRN,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Tìm theo SRN_NO',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                suffixIcon: IconButton(
                  onPressed: _loadData,
                  icon: const Icon(Icons.search),
                ),
              ),
              onChanged: (value) {
                _controllerSRN.value = _controllerSRN.value.copyWith(
                  text: value.toUpperCase(),
                  selection: TextSelection.collapsed(offset: value.length),
                );
              },
              onSubmitted: (_) => _loadData(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickPlanDate,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(_selectedDateLabel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isPendingMode && _selectedIds.isNotEmpty
                        ? _confirmSelected
                        : null,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text('Xác nhận (${_selectedIds.length})'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Xóa bộ lọc',
                  onPressed: _resetFilters,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildViewButton(mode: ResultViewMode.pending, label: 'Đang chờ'),
                  _buildViewButton(mode: ResultViewMode.history, label: 'Lịch sử'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Kết quả: $_resultSummary',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Text(
                  _selectedDateLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildTableHeader(),
            const SizedBox(height: 8),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (_isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (_errorMessage != null) {
                    return Center(child: Text(_errorMessage!));
                  }

                  if (data.isEmpty) {
                    return const Center(
                      child: Text('Không có dữ liệu phù hợp với bộ lọc hiện tại.'),
                    );
                  }

                  final groupedData = _groupedData;

                  return ListView.builder(
                    itemCount: groupedData.length,
                    itemBuilder: (context, index) {
                      final group = groupedData[index];
                      final locator = group.locator;
                      final srnLabel = _buildSrnLabel(group);
                      final isSelected =
                          group.ids.isNotEmpty &&
                          group.ids.every(_selectedIds.contains);
                      final totalQty = group.rows.fold<int>(
                        0,
                        (sum, item) => sum + _toInt(item['qty']),
                      );
                      final reqQty = group.rows.fold<int>(
                        0,
                        (sum, item) => sum + _toInt(item['req_qty']),
                      );
                      final docRefs = group.rows
                          .map((item) => item['doc_ref']?.toString() ?? '')
                          .where((value) => value.isNotEmpty)
                          .toSet()
                          .toList()
                        ..sort();
                      final planDates = group.rows
                          .map((item) => _formatDisplayDate(item['plan_date']))
                          .toSet()
                          .toList();
                      final confirmDates = group.rows
                          .map((item) => _formatDisplayDate(item['confirm_date']))
                          .toSet()
                          .toList();

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Thông tin thêm'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('SRN_NO: ${docRefs.join(', ')}'),
                                    Text('Locator: $locator'),
                                    Text('SRN: $srnLabel'),
                                    Text('Qty: $totalQty'),
                                    Text('Req Qty: $reqQty'),
                                    Text('Plan Date: ${planDates.join(', ')}'),
                                    Text('Confirm Date: ${confirmDates.join(', ')}'),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                    child: const Text('Đóng'),
                                    onPressed: () => Navigator.of(context).pop(),
                                  )
                                ],
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        locator,
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'SRN: ${srnLabel.isEmpty ? '-' : srnLabel}',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    srnLabel.isEmpty ? '-' : srnLabel,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.blueAccent,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: _isPendingMode
                                        ? Checkbox(
                                            value: isSelected,
                                            onChanged: (checked) =>
                                          _toggleGroupSelection(group, checked),
                                          )
                                        : Icon(
                                            Icons.history_toggle_off,
                                            color: Colors.grey.shade600,
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}