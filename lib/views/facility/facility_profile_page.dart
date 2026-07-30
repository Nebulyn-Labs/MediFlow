import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:med_supply_prototype/constants/colors.dart';
import 'package:med_supply_prototype/services/firebase_service.dart';
import 'package:med_supply_prototype/models/facility.dart';
import 'package:intl/intl.dart';

class FacilityProfilePage extends ConsumerStatefulWidget {
  final String facilityId;

  const FacilityProfilePage({super.key, required this.facilityId});

  @override
  ConsumerState<FacilityProfilePage> createState() =>
      _FacilityProfilePageState();
}

class _FacilityProfilePageState extends ConsumerState<FacilityProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _regionController;
  bool _isLoading = true;
  bool _isSaving = false;
  Facility? _facility;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _regionController = TextEditingController();
    _loadFacility();
  }

  Future<void> _loadFacility() async {
    try {
      final facility = await ref
          .read(firebaseServiceProvider)
          .getFacility(widget.facilityId);
      if (!mounted) return;
      if (facility != null) {
        setState(() {
          _facility = facility;
          _nameController.text = facility.name;
          _regionController.text = facility.region;
        });
      }
    } catch (e) {
      // Handle or log error if needed
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      await ref.read(firebaseServiceProvider).updateFacility(
        widget.facilityId,
        {
          'name': _nameController.text.trim(),
          'region': _regionController.text.trim(),
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Profile updated successfully'),
            backgroundColor: Colors.green.shade600,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update profile: $e'),
            backgroundColor: MediColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_facility == null) {
      return const Center(child: Text('Facility not found'));
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Profile & Settings',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: MediColors.textPrimary,
              ),
            ),
            const SizedBox(height: 32),
            Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Edit Profile Details',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Facility Name',
                              prefixIcon: Icon(Icons.business_rounded),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'Name is required'
                                    : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _regionController,
                            decoration: const InputDecoration(
                              labelText: 'Region',
                              prefixIcon: Icon(Icons.map_rounded),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'Region is required'
                                    : null,
                          ),
                          const SizedBox(height: 32),
                          const Text(
                            'System Information',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildReadOnlyField('Email', _facility!.email),
                          const SizedBox(height: 12),
                          _buildReadOnlyField(
                              'Facility Type', _facility!.type.toUpperCase()),
                          const SizedBox(height: 12),
                          _buildReadOnlyField('Coordinates',
                              '${_facility!.latitude.toStringAsFixed(4)}, ${_facility!.longitude.toStringAsFixed(4)}'),
                          const SizedBox(height: 12),
                          _buildReadOnlyField('Created At',
                              DateFormat('yMMMd').format(_facility!.createdAt)),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _isSaving ? null : _saveChanges,
                              child: _isSaving
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Save Changes'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: const TextStyle(
              color: MediColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: MediColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
