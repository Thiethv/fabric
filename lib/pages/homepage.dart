import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stock_submat/services/supabase_func.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final supaFunc = SupabaseFunc();
  final _controllerSRN = TextEditingController();
  final FocusNode _srnFocusNode = FocusNode();
  Timer? _searchDebounce;

  String selectedDocRef = '';

  String itemTitle = '';
  String subTitle = '';
  String textTitle = '';
  String srntext = '';

  List<Map<String, dynamic>> data = [];
  List<String> docRefOptions = [];
  bool isLoadingDocRefs = false;

  @override
  void initState() {
    super.initState();
    _srnFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
    _loadDocRefs();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _controllerSRN.dispose();
    _srnFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadDocRefs({String? search}) async {
    setState(() {
      isLoadingDocRefs = true;
    });

    try {
      final refs = await supaFunc.fetchDocRefList(search: search);
      if (mounted) {
        setState(() {
          docRefOptions = refs;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi load doc_ref: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoadingDocRefs = false;
        });
      }
    }
  }

  void _selectDocRef(String docRef) {
    setState(() {
      selectedDocRef = docRef;
      srntext = docRef;
    });
    _controllerSRN.text = docRef;
    _controllerSRN.selection = TextSelection.collapsed(offset: docRef.length);
    _srnFocusNode.unfocus();
    clickLocator(docRef);
  }

  Future<void> _openDocRefPicker() async {
    if (docRefOptions.isEmpty && !isLoadingDocRefs) {
      await _loadDocRefs();
    }

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        String localSearch = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final sheetMaxHeight = MediaQuery.of(context).size.height * 0.75;
            final filtered = docRefOptions
                .where((e) => localSearch.isEmpty || e.toUpperCase().contains(localSearch))
                .take(200)
                .toList();

            return SafeArea(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                child: SizedBox(
                  height: sheetMaxHeight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        TextField(
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'Tìm SRN (doc_ref)',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (v) => setModalState(() {
                            localSearch = v.trim().toUpperCase();
                          }),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: isLoadingDocRefs
                              ? const Center(child: CircularProgressIndicator())
                              : filtered.isEmpty
                                  ? const Center(child: Text('Không có SRN phù hợp'))
                                  : ListView.separated(
                                      itemCount: filtered.length,
                                      separatorBuilder: (_, __) => const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        final docRef = filtered[index];
                                        return ListTile(
                                          title: Text(docRef),
                                          onTap: () {
                                            Navigator.of(context).pop();
                                            _selectDocRef(docRef);
                                          },
                                        );
                                      },
                                    ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> clickLocator(srnNo) async {
    final safe = srnNo.toString().replaceAll("'", "''");
    final result = await supaFunc.fetchSrn(
      'fb_srn',
      ' locator, sum(qty) as qty ',
      " doc_ref LIKE '%$safe%' AND is_confirm IS FALSE ",
      ' locator '
    );
    if (result.isNotEmpty) {
      final nextData = List<Map<String, dynamic>>.from(result);
      setState(() {
        data = nextData;
        srntext = srnNo.toString();
      });
      return data;
    } else {
      setState(() {
        data = [];
        srntext = srnNo.toString();
      });
      return [];
    }
  }

  Future<bool> _confirmDismissItem({
    required BuildContext context,
    required String docRef,
    required String locator,
  }) async {
    final approved = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Xác nhận'),
            content: Text('Xác nhận hạ $locator '),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Huỷ'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Xác nhận'),
              ),
            ],
          ),
        ) ??
        false;

    if (!approved) return false;

    try {
      await supaFunc.confirmSrnLocator(docRef: docRef, locator: locator);
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi confirm: $e')),
      );
      return false;
    }
  }

  void _removeLocatorRow({required String docRef, required String locator}) {
    setState(() {
      data.removeWhere((e) =>
          (e['locator'] ?? '').toString() == locator);
    });

    if (data.where((e) => (e['locator'] ?? '').toString() == locator).isEmpty) {
      _loadDocRefs();
    }
  }

  Future<void> _confirmAndRemove({
    required BuildContext context,
    required String docRef,
    required String locator,
  }) async {
    final ok = await _confirmDismissItem(context: context, docRef: docRef, locator: locator);
    if (!ok) return;
    _removeLocatorRow(docRef: docRef, locator: locator);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã confirm: $docRef @ $locator')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _controllerSRN.text.trim().toUpperCase();
    final docRefSuggestions = docRefOptions
        .where((e) => query.isEmpty || e.toUpperCase().contains(query))
        .take(30)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('APP Fabric', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 30, color: Colors.blue),),
        
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _controllerSRN,
              focusNode: _srnFocusNode,
              decoration: InputDecoration(
                hintText: 'Chọn SRN',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: isLoadingDocRefs
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Chọn SRN',
                  icon: const Icon(Icons.arrow_drop_down),
                  onPressed: _openDocRefPicker,
                ),
              ),
              onChanged: (value) {
                final upper = value.toUpperCase();
                if (_controllerSRN.text != upper) {
                  _controllerSRN.value = _controllerSRN.value.copyWith(
                    text: upper,
                    selection: TextSelection.collapsed(offset: upper.length),
                  );
                }

                setState(() {
                  selectedDocRef = upper;
                  srntext = upper;
                });

                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 350), () {
                  final text = _controllerSRN.text.trim();
                  if (text.isEmpty) {
                    setState(() {
                      data = [];
                      srntext = '';
                      selectedDocRef = '';
                    });
                    _loadDocRefs();
                    return;
                  }
                  clickLocator(text);
                  _loadDocRefs(search: text);
                });
              },
              onSubmitted: (_) {
                final text = _controllerSRN.text.trim();
                if (text.isNotEmpty) clickLocator(text);
              },
            ),

            if (_srnFocusNode.hasFocus && docRefSuggestions.isNotEmpty) ...[
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: Material(
                  elevation: 2,
                  borderRadius: BorderRadius.circular(10),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: docRefSuggestions.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final docRef = docRefSuggestions[index];
                      return ListTile(
                        dense: true,
                        title: Text(docRef),
                        onTap: () => _selectDocRef(docRef),
                      );
                    },
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),

            if (srntext.isNotEmpty)

            if (data.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 5.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        'LOCATOR',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'QTY',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        'CONFIRM',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],

            Expanded(
              child: data.isEmpty
                  ? const Center(child: Text('Chọn SRN để xem Locator + Qty'))
                  : ListView.builder(
                      itemCount: data.length,
                      itemBuilder: (context, index) {
                        final item = data[index];

                        final docRef = selectedDocRef.isNotEmpty
                            ? selectedDocRef
                            : _controllerSRN.text.trim();
                        final locator = (item['locator'] ?? '').toString();
                        final qty = item['qty'] ?? item['sum'] ?? item['sum(qty)'];

                        return Dismissible(
                          key: ValueKey('$docRef|$locator|$index'),
                          direction: DismissDirection.startToEnd,
                          confirmDismiss: (_) => _confirmDismissItem(
                            context: context,
                            docRef: docRef,
                            locator: locator,
                          ),
                          onDismissed: (_) {
                            _removeLocatorRow(docRef: docRef, locator: locator);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Đã confirm: $docRef @ $locator')),
                            );
                          },
                          background: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            alignment: Alignment.centerLeft,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.white),
                                SizedBox(width: 10),
                                Text(
                                  'Kéo để xác nhận',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          child: Card(
                            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              title: Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      locator,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      qty.toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20,
                                        color: Colors.blue,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: IconButton(
                                      tooltip: 'Xác nhận',
                                      onPressed: () => _confirmAndRemove(
                                        context: context,
                                        docRef: docRef,
                                        locator: locator,
                                      ),
                                      icon: const Icon(Icons.check_circle, color: Colors.green),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            )
          ]
        ),
      ),
    );
  }
}