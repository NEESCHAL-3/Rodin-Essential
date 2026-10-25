import 'dart:async';

import 'package:flutter/material.dart';

import 'backend/rodin_backend.dart';

import 'backend/audio_backend.dart';
import 'backend/audio_codec_capabilities.dart';
import 'backend/audio_ldac_quality.dart';
import 'backend/audio_device_profile.dart';

class AudioHubScreen extends StatefulWidget {
  const AudioHubScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<AudioHubScreen> createState() => _AudioHubScreenState();
}

class _AudioHubScreenState extends State<AudioHubScreen>
    with WidgetsBindingObserver {
  AudioBluetoothStatus _status = AudioBluetoothStatus.unavailable;
  Timer? _permissionTimer;
  Timer? _deviceTimer;
  Timer? _codecTimer;
  Timer? _postConnectCodecTimer;
  Timer? _connectionWatchTimer;
  int? _observedConnectionGeneration;
  Timer? _companionTimer;
  Timer? _companionAssociationTimer;
  Timer? _applyTimer;
  Timer? _verifyTimer;
  Timer? _profileTimer;
  Timer? _saveProfileTimer;
  Timer? _deleteProfileTimer;
  bool _savingProfile = false;
  String _saveProfileMessage = '';
  bool _deletingProfile = false;
  bool _updatingAutoRestore = false;
  String _autoRestoreMessage = '';
  Timer? _autoRestoreTimer;
  int _autoRestoreOperation = 0;
  String _deleteProfileMessage = '';
  int _deleteProfileOperation = 0;
  bool _applyingCodec = false;
  String _applyMessage = '';
  int? _verifiedCodec;
  int? _verifiedSampleRate;
  int? _verifiedBitDepth;
  int? _verifiedLdacQuality;
  int? _applyConnectionGeneration;
  int? _verifiedConnectionGeneration;
  String _codecDiagnostic = 'NOT_REQUESTED';
  String _companionStatus = 'NOT_REQUESTED';
  String _companionAssociationResult = 'NOT_REQUESTED';
  bool _associatingCompanion = false;
  AudioCodecSnapshot? _codecSnapshot;
  AudioDeviceProfile? _savedProfile;
  String _savedProfileStatus = 'NOT_REQUESTED';
  int? _selectedCodec;
  int? _selectedSampleRate;
  int? _selectedBitDepth;
  int? _selectedLdacQuality;
  bool _codecSelectionDirty = false;
  String _connectedDevice = '';
  bool _deviceLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _startConnectionWatch();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      _startConnectionWatch();
    } else {
      _connectionWatchTimer?.cancel();
      _connectionWatchTimer = null;
      _postConnectCodecTimer?.cancel();
      _postConnectCodecTimer = null;
    }
  }

  void _startConnectionWatch() {
    _connectionWatchTimer?.cancel();

    final backend = AudioBackend.instance;
    _observedConnectionGeneration = backend.connectionGeneration;

    _connectionWatchTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final generation = backend.connectionGeneration;
      if (generation < 0) return;

      final previous = _observedConnectionGeneration;
      if (previous == null || previous < 0) {
        _observedConnectionGeneration = generation;
        return;
      }

      if (generation == previous) return;

      // Do not consume a reconnection while Apply is in progress.
      // Process it during the next available check.
      if (_applyingCodec) return;

      _observedConnectionGeneration = generation;
      _refresh();
    });
  }

  void _refresh() {
    if (!mounted) return;

    final backend = AudioBackend.instance;
    backend.cancelPendingApply();
    final status = backend.bluetoothStatus;
    _observedConnectionGeneration = backend.connectionGeneration;

    _deviceTimer?.cancel();
    _deviceTimer = null;
    _codecTimer?.cancel();
    _codecTimer = null;
    _postConnectCodecTimer?.cancel();
    _postConnectCodecTimer = null;
    _profileTimer?.cancel();
    _profileTimer = null;
    _saveProfileTimer?.cancel();
    _saveProfileTimer = null;
    _autoRestoreTimer?.cancel();
    _autoRestoreTimer = null;
    _autoRestoreOperation++;
    _deleteProfileTimer?.cancel();
    _deleteProfileTimer = null;
    _deleteProfileOperation++;
    _companionTimer?.cancel();
    _companionTimer = null;

    setState(() {
      _codecDiagnostic = 'NOT_REQUESTED';
      if (!_associatingCompanion) {
        _companionStatus = 'NOT_REQUESTED';
      }
      _applyTimer?.cancel();
      _applyTimer = null;
      _verifyTimer?.cancel();
      _verifyTimer = null;
      _applyingCodec = false;
      _applyMessage = '';
      _verifiedCodec = null;
      _verifiedSampleRate = null;
      _verifiedBitDepth = null;
      _verifiedLdacQuality = null;
      _applyConnectionGeneration = null;
      _verifiedConnectionGeneration = null;
      _codecSnapshot = null;
      _savedProfile = null;
      _savedProfileStatus = 'NOT_REQUESTED';
      _savingProfile = false;
      _saveProfileMessage = '';
      _deletingProfile = false;
      _deleteProfileMessage = '';
      _selectedCodec = null;
      _selectedSampleRate = null;
      _selectedBitDepth = null;
      _selectedLdacQuality = null;
      _codecSelectionDirty = false;
      _status = status;
      _connectedDevice = '';
      _deviceLoading = status == AudioBluetoothStatus.enabled;
    });

    if (status != AudioBluetoothStatus.enabled) return;

    if (!backend.refreshConnectedDevice()) {
      setState(() => _deviceLoading = false);
      return;
    }

    var attempts = 0;

    _deviceTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      attempts++;

      final name = backend.connectedDeviceName;

      if (name.isNotEmpty || attempts >= 12) {
        timer.cancel();
        _deviceTimer = null;

        setState(() {
          _connectedDevice = name;
          _deviceLoading = false;
        });

        if (name.isNotEmpty) {
          _requestCompanionStatus();
          _requestCodecDiagnostic();
          _schedulePostConnectCodecCheck();
          _requestSavedProfile();
        }
      }
    });
  }

  void _requestSavedProfile() {
    if (!mounted || _deletingProfile) return;

    final backend = AudioBackend.instance;

    _profileTimer?.cancel();
    _profileTimer = null;

    if (!backend.requestSavedProfile()) {
      setState(() {
        _savedProfile = null;
        _savedProfileStatus = 'BACKEND_UNAVAILABLE';
      });
      return;
    }

    setState(() {
      _savedProfile = null;
      _savedProfileStatus = 'PENDING';
    });

    var attempts = 0;

    _profileTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      attempts++;
      final result = backend.savedProfileResult;

      if (result != 'PENDING' && result != 'NOT_REQUESTED') {
        timer.cancel();
        _profileTimer = null;

        final profile = AudioDeviceProfile.parse(result);

        setState(() {
          _savedProfile = profile;
          _savedProfileStatus =
              result.startsWith('PROFILE_FOUND;') && profile == null
              ? 'INVALID_PROFILE'
              : profile != null
              ? 'PROFILE_FOUND'
              : result;
        });
      } else if (attempts >= 20) {
        timer.cancel();
        _profileTimer = null;

        setState(() {
          _savedProfile = null;
          _savedProfileStatus = 'TIMEOUT';
        });
      }
    });
  }

  void _requestCompanionStatus() {
    if (!mounted || _associatingCompanion) return;

    final backend = AudioBackend.instance;

    _companionTimer?.cancel();
    _companionTimer = null;

    if (!backend.requestCompanionStatus()) {
      setState(() => _companionStatus = 'BACKEND_UNAVAILABLE');
      return;
    }

    setState(() => _companionStatus = 'PENDING');

    var attempts = 0;

    _companionTimer = Timer.periodic(const Duration(milliseconds: 250), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      attempts++;
      final result = backend.companionStatusResult;

      if (result != 'PENDING' && result != 'NOT_REQUESTED') {
        timer.cancel();
        _companionTimer = null;
        setState(() => _companionStatus = result);
      } else if (attempts >= 20) {
        timer.cancel();
        _companionTimer = null;
        setState(() => _companionStatus = 'TIMEOUT');
      }
    });
  }

  void _requestCompanionAssociation() {
    if (!mounted ||
        _associatingCompanion ||
        _companionStatus != 'NOT_ASSOCIATED') {
      return;
    }

    final backend = AudioBackend.instance;

    _companionAssociationTimer?.cancel();
    _companionAssociationTimer = null;

    if (!backend.requestCompanionAssociation()) {
      setState(() {
        _companionAssociationResult = 'REQUEST_FAILED';
        _associatingCompanion = false;
      });
      return;
    }

    setState(() {
      _companionAssociationResult = 'PENDING';
      _associatingCompanion = true;
    });

    _companionAssociationTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        final result = backend.companionAssociationResult;

        const pendingStates = {
          'NOT_REQUESTED',
          'PENDING',
          'REQUEST_STARTED',
          'WAITING_FOR_USER',
          'AWAITING_CONFIRMATION',
        };

        if (pendingStates.contains(result)) {
          if (_companionAssociationResult != result) {
            setState(() => _companionAssociationResult = result);
          }
          return;
        }

        timer.cancel();
        _companionAssociationTimer = null;

        setState(() {
          _companionAssociationResult = result;
          _associatingCompanion = false;
        });

        if (result == 'ASSOCIATED' || result == 'ALREADY_ASSOCIATED') {
          _requestCompanionStatus();
        } else if (result == 'DEVICE_CHANGED') {
          _refresh();
        }
      },
    );
  }

  void _schedulePostConnectCodecCheck() {
    _postConnectCodecTimer?.cancel();

    final backend = AudioBackend.instance;
    final generation = backend.connectionGeneration;

    if (generation < 0) return;

    _postConnectCodecTimer = Timer(const Duration(milliseconds: 2500), () {
      _postConnectCodecTimer = null;

      if (!mounted ||
          _applyingCodec ||
          _codecSelectionDirty ||
          backend.connectionGeneration != generation) {
        return;
      }

      _requestCodecDiagnostic();
    });
  }

  void _requestCodecDiagnostic() {
    if (_applyingCodec) return;

    final backend = AudioBackend.instance;

    _codecTimer?.cancel();
    _codecTimer = null;

    if (!backend.requestCodecDiagnostic()) {
      setState(() => _codecDiagnostic = 'BACKEND_UNAVAILABLE');
      return;
    }

    setState(() => _codecDiagnostic = 'PENDING');

    var attempts = 0;

    _codecTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      attempts++;
      final result = backend.codecDiagnosticResult;

      if (result != 'PENDING' && result != 'NOT_REQUESTED') {
        timer.cancel();
        _codecTimer = null;
        setState(() {
          _codecDiagnostic = result;
          _codecSnapshot = AudioCodecSnapshot.parse(result);

          final snapshot = _codecSnapshot;
          if (snapshot != null) {
            final capability = snapshot.capabilityFor(snapshot.codec);

            if (capability != null && !_codecSelectionDirty) {
              _selectedCodec = snapshot.codec;

              final rates = capability.availableSampleRates;
              final depths = capability.availableBitDepths;

              _selectedSampleRate = rates.contains(snapshot.sampleRate)
                  ? snapshot.sampleRate
                  : (rates.isNotEmpty ? rates.first : null);

              _selectedBitDepth = depths.contains(snapshot.bitDepth)
                  ? snapshot.bitDepth
                  : (depths.isNotEmpty ? depths.first : null);

              _selectedLdacQuality =
                  snapshot.codec == 4 &&
                      AudioLdacQuality.isKnown(snapshot.codecSpecific1)
                  ? snapshot.codecSpecific1
                  : null;
            }
          }
        });
      } else if (attempts >= 20) {
        timer.cancel();
        _codecTimer = null;
        setState(() => _codecDiagnostic = 'TIMEOUT');
      }
    });
  }

  Widget _buildSavedProfileCard() {
    final profile = _savedProfile;

    String description;

    if (profile != null) {
      final codec =
          AudioCodecCapability.codecNames[profile.codec] ??
          'Codec ${profile.codec}';

      final rate =
          AudioCodecCapability.sampleRateNames[profile.sampleRate] ??
          'Unknown rate (${profile.sampleRate})';

      final bits =
          AudioCodecCapability.bitDepthNames[profile.bits] ??
          'Unknown depth (${profile.bits})';

      description = '$codec · $rate · $bits';
    } else {
      description = switch (_savedProfileStatus) {
        'NOT_REQUESTED' => 'Waiting for a connected device',
        'PENDING' => 'Checking saved device profile...',
        'NO_PROFILE' => 'No saved configuration for this device',
        'TIMEOUT' => 'Saved profile lookup timed out',
        'INVALID_PROFILE' => 'Saved profile data is invalid',
        'ACTIVE_DEVICE_UNVERIFIED' =>
          'Android could not verify the active audio device',
        'PERMISSION_REQUIRED' => 'Bluetooth permission required',
        'DEVICE_UNAVAILABLE' => 'No active audio device available',
        'A2DP_UNAVAILABLE' => 'Bluetooth audio service unavailable',
        final other => 'Profile lookup: $other',
      };
    }

    return Card(
      child: ListTile(
        leading: const Icon(Icons.bookmark_outline_rounded),
        title: const Text('Saved device profile'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(description),
            if (profile != null &&
                profile.codec == 4 &&
                AudioLdacQuality.isKnown(profile.ldacQuality)) ...[
              const SizedBox(height: 4),
              Text(
                'Saved LDAC quality: '
                '${AudioLdacQuality.names[profile.ldacQuality]}',
              ),
            ],
            if (profile != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      profile.autoRestore
                          ? 'Auto Restore enabled'
                          : 'Auto Restore disabled',
                    ),
                  ),
                  if (_updatingAutoRestore)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  Switch(
                    value: profile.autoRestore,
                    onChanged:
                        _applyingCodec ||
                            _savingProfile ||
                            _deletingProfile ||
                            _updatingAutoRestore
                        ? null
                        : _setAutoRestore,
                  ),
                ],
              ),
              if (_autoRestoreMessage.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(_autoRestoreMessage),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed:
                      _applyingCodec || _savingProfile || _deletingProfile
                      ? null
                      : _confirmDeleteSavedProfile,
                  icon: _deletingProfile
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline_rounded),
                  label: Text(
                    _deletingProfile ? 'Deleting...' : 'Delete profile',
                  ),
                ),
              ),
            ],
            if (_deleteProfileMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_deleteProfileMessage),
            ],
          ],
        ),
      ),
    );
  }

  String get _codecDiagnosticLabel {
    final value = _codecDiagnostic;

    if (value.startsWith('OK;')) {
      final fields = <String, String>{};

      for (final part in value.split(';').skip(1)) {
        final separator = part.indexOf('=');
        if (separator > 0) {
          fields[part.substring(0, separator)] = part.substring(separator + 1);
        }
      }

      final codec = switch (fields['codec']) {
        '0' => 'SBC',
        '1' => 'AAC',
        '2' => 'aptX',
        '3' => 'aptX HD',
        '4' => 'LDAC',
        '5' => 'LC3',
        final other => 'Codec $other',
      };

      final sampleRate = switch (fields['sampleRate']) {
        '1' => '44.1 kHz',
        '2' => '48 kHz',
        '4' => '88.2 kHz',
        '8' => '96 kHz',
        final other => 'Unknown ($other)',
      };

      final bits = switch (fields['bits']) {
        '1' => '16-bit',
        '2' => '24-bit',
        '4' => '32-bit',
        final other => 'Unknown ($other)',
      };

      return '$codec · $sampleRate · $bits';
    }

    return switch (value) {
      'NOT_REQUESTED' => 'Waiting for a connected audio device',
      'PENDING' => 'Reading active Bluetooth codec...',
      'TIMEOUT' => 'Codec diagnostic timed out',
      'BACKEND_UNAVAILABLE' => 'Codec backend unavailable',
      final other => 'Codec diagnostic: $other',
    };
  }

  void _applyCodecSelection() {
    if (_applyingCodec || _savingProfile || _deletingProfile) return;

    final codec = _selectedCodec;
    final rate = _selectedSampleRate;
    final bits = _selectedBitDepth;
    final snapshot = _codecSnapshot;
    final ldacQuality = codec == 4 ? _selectedLdacQuality : null;

    if (codec == null || rate == null || bits == null || snapshot == null) {
      return;
    }

    final capability = snapshot.capabilityFor(codec);

    if (capability == null ||
        !capability.availableSampleRates.contains(rate) ||
        !capability.availableBitDepths.contains(bits)) {
      return;
    }

    final backend = AudioBackend.instance;
    final connectionGeneration = backend.connectionGeneration;

    if (connectionGeneration < 0) {
      setState(() {
        _applyMessage = 'Unable to verify Bluetooth connection.';
      });
      return;
    }

    setState(() {
      _verifiedCodec = null;
      _verifiedSampleRate = null;
      _verifiedBitDepth = null;
      _verifiedLdacQuality = null;
      _verifiedConnectionGeneration = null;
      _applyConnectionGeneration = connectionGeneration;
    });

    // Apply takes priority over automatic diagnostics.
    _codecTimer?.cancel();
    _codecTimer = null;

    if (!backend.requestApplyCodecWithQuality(
      codec,
      rate,
      bits,
      ldacQuality ?? -1,
    )) {
      setState(() => _applyMessage = 'Unable to send codec request.');
      return;
    }

    _applyTimer?.cancel();
    _verifyTimer?.cancel();
    _verifyTimer = null;

    setState(() {
      _applyingCodec = true;
      _applyMessage = 'Requesting codec change...';
    });

    var attempts = 0;

    _applyTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      attempts++;

      if (backend.connectionGeneration != _applyConnectionGeneration) {
        timer.cancel();
        _applyTimer = null;
        setState(() {
          _applyingCodec = false;
          _applyConnectionGeneration = null;
          _applyMessage = 'Bluetooth connection changed during Apply.';
        });
        return;
      }

      final result = backend.applyCodecResult;

      if (result == 'PENDING' || result == 'NOT_REQUESTED') {
        if (attempts < 20) return;

        timer.cancel();
        _applyTimer = null;
        setState(() {
          _applyingCodec = false;
          _applyMessage = 'Codec request timed out.';
        });
        return;
      }

      timer.cancel();
      _applyTimer = null;

      if (result != 'REQUEST_SENT') {
        setState(() {
          _applyingCodec = false;
          _applyMessage = 'Codec request failed: $result';
        });
        return;
      }

      setState(() {
        _applyMessage = 'Request sent. Verifying active codec...';
      });

      _codecTimer?.cancel();
      _codecTimer = null;

      if (!backend.requestCodecDiagnostic()) {
        setState(() {
          _applyingCodec = false;
          _applyMessage = 'Unable to verify the active codec.';
        });
        return;
      }

      // Java invalidates the previous result when accepting the request.
      // The diagnostic may finish before our first read.
      var checks = 0;
      _verifyTimer = Timer.periodic(const Duration(milliseconds: 300), (
        verifyTimer,
      ) {
        if (!mounted) {
          verifyTimer.cancel();
          return;
        }

        checks++;

        if (backend.connectionGeneration != _applyConnectionGeneration) {
          verifyTimer.cancel();
          _verifyTimer = null;
          setState(() {
            _applyingCodec = false;
            _applyConnectionGeneration = null;
            _applyMessage = 'Bluetooth connection changed during verification.';
          });
          return;
        }

        final diagnostic = backend.codecDiagnosticResult;
        final verified = AudioCodecSnapshot.parse(diagnostic);

        if (verified != null &&
            verified.codec == codec &&
            verified.sampleRate == rate &&
            verified.bitDepth == bits &&
            (ldacQuality == null || verified.codecSpecific1 == ldacQuality)) {
          verifyTimer.cancel();
          _verifyTimer = null;

          setState(() {
            _applyingCodec = false;
            _codecDiagnostic = diagnostic;
            _codecSnapshot = verified;
            _verifiedCodec = codec;
            _verifiedSampleRate = rate;
            _verifiedBitDepth = bits;
            _verifiedLdacQuality = ldacQuality;
            _codecSelectionDirty = false;
            _verifiedConnectionGeneration = connectionGeneration;
            _applyConnectionGeneration = null;
            _applyMessage = 'Codec configuration verified.';
          });
          return;
        }

        if (checks >= 15) {
          verifyTimer.cancel();
          _verifyTimer = null;
          setState(() {
            _applyingCodec = false;
            _applyMessage =
                'Android did not confirm the requested configuration.';
          });
        }
      });
    });
  }

  void _saveCodecProfile() {
    if (!mounted || _applyingCodec || _savingProfile || _deletingProfile)
      return;

    final codec = _selectedCodec;
    final rate = _selectedSampleRate;
    final bits = _selectedBitDepth;

    if (codec == null ||
        rate == null ||
        bits == null ||
        codec != _verifiedCodec ||
        rate != _verifiedSampleRate ||
        bits != _verifiedBitDepth ||
        (codec == 4 && _selectedLdacQuality != _verifiedLdacQuality)) {
      setState(() {
        _saveProfileMessage =
            'Apply and verify this configuration before saving.';
      });
      return;
    }

    final backend = AudioBackend.instance;
    final connectionGeneration = backend.connectionGeneration;

    if (_verifiedConnectionGeneration == null ||
        connectionGeneration < 0 ||
        connectionGeneration != _verifiedConnectionGeneration) {
      setState(() {
        _verifiedCodec = null;
        _verifiedSampleRate = null;
        _verifiedBitDepth = null;
        _verifiedConnectionGeneration = null;
        _saveProfileMessage =
            'Bluetooth connection changed. Apply again before saving.';
      });
      return;
    }

    final ldacQuality = codec == 4 ? (_selectedLdacQuality ?? -1) : -1;

    if (!backend.requestSaveProfileWithQuality(
      codec,
      rate,
      bits,
      ldacQuality,
      connectionGeneration,
    )) {
      setState(() {
        _saveProfileMessage = 'Unable to request profile save.';
      });
      return;
    }

    _saveProfileTimer?.cancel();

    setState(() {
      _savingProfile = true;
      _saveProfileMessage = 'Saving device profile...';
    });

    var attempts = 0;

    _saveProfileTimer = Timer.periodic(const Duration(milliseconds: 250), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      attempts++;
      final result = backend.saveProfileResult;

      if (result == 'PENDING' || result == 'NOT_REQUESTED') {
        if (attempts < 20) return;

        timer.cancel();
        _saveProfileTimer = null;

        setState(() {
          _savingProfile = false;
          _saveProfileMessage = 'Profile save timed out.';
        });
        return;
      }

      timer.cancel();
      _saveProfileTimer = null;

      if (result == 'PROFILE_SAVED') {
        setState(() {
          _savingProfile = false;
          _saveProfileMessage = 'Device profile saved successfully.';
        });
        _requestSavedProfile();
      } else {
        setState(() {
          _savingProfile = false;
          _saveProfileMessage = 'Profile save failed: $result';
        });
      }
    });
  }

  Future<void> _confirmDeleteSavedProfile() async {
    if (!mounted ||
        _savedProfile == null ||
        _applyingCodec ||
        _savingProfile ||
        _deletingProfile) {
      return;
    }

    final connectionGeneration = AudioBackend.instance.connectionGeneration;
    if (connectionGeneration < 0) return;

    final deviceName = _connectedDevice;
    final profileAtConfirmation = _savedProfile;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete saved profile?'),
        content: Text(
          'Remove the saved audio configuration for $deviceName? '
          'This will not disconnect the device or change the '
          'currently active audio codec.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    if (_savedProfile != profileAtConfirmation ||
        _applyingCodec ||
        _savingProfile ||
        _deletingProfile) {
      setState(() {
        _deleteProfileMessage = 'Profile state changed. Deletion cancelled.';
      });
      return;
    }

    if (AudioBackend.instance.connectionGeneration != connectionGeneration ||
        _connectedDevice != deviceName) {
      setState(() {
        _deleteProfileMessage = 'Bluetooth device changed. Deletion cancelled.';
      });
      return;
    }

    _deleteSavedProfile();
  }

  void _deleteSavedProfile() {
    if (!mounted ||
        _applyingCodec ||
        _savingProfile ||
        _deletingProfile ||
        _savedProfile == null) {
      return;
    }

    final backend = AudioBackend.instance;
    final connectionGeneration = backend.connectionGeneration;

    if (connectionGeneration < 0) {
      setState(() {
        _deleteProfileMessage = 'Unable to verify the Bluetooth connection.';
      });
      return;
    }

    if (!backend.requestDeleteProfile(connectionGeneration)) {
      setState(() {
        _deleteProfileMessage = 'Unable to request profile deletion.';
      });
      return;
    }

    _profileTimer?.cancel();
    _profileTimer = null;
    _deleteProfileTimer?.cancel();
    final operation = ++_deleteProfileOperation;

    setState(() {
      _deletingProfile = true;
      _deleteProfileMessage = 'Deleting saved device profile...';
    });

    var attempts = 0;

    _deleteProfileTimer = Timer.periodic(const Duration(milliseconds: 250), (
      timer,
    ) {
      if (!mounted || operation != _deleteProfileOperation) {
        timer.cancel();
        return;
      }

      attempts++;
      final result = backend.deleteProfileResult;

      if (result == 'PENDING' || result == 'NOT_REQUESTED') {
        if (attempts < 20) return;

        timer.cancel();
        _deleteProfileTimer = null;

        setState(() {
          _deletingProfile = false;
          _deleteProfileMessage = 'Profile deletion timed out.';
        });
        return;
      }

      timer.cancel();
      _deleteProfileTimer = null;

      if (result == 'PROFILE_DELETED' || result == 'NO_PROFILE') {
        setState(() {
          _deletingProfile = false;
          _savedProfile = null;
          _savedProfileStatus = 'NO_PROFILE';
          _deleteProfileMessage = result == 'PROFILE_DELETED'
              ? 'Saved device profile deleted.'
              : 'No saved profile remains for this device.';
        });
      } else {
        setState(() {
          _deletingProfile = false;
          _deleteProfileMessage = 'Profile deletion failed: $result';
        });
      }
    });
  }

  void _setAutoRestore(bool enabled) {
    if (!mounted ||
        _savedProfile == null ||
        _applyingCodec ||
        _savingProfile ||
        _deletingProfile ||
        _updatingAutoRestore) {
      return;
    }

    final backend = AudioBackend.instance;
    final connectionGeneration = backend.connectionGeneration;

    if (connectionGeneration < 0) {
      setState(() {
        _autoRestoreMessage = 'Unable to verify Bluetooth connection.';
      });
      return;
    }

    final profileAtRequest = _savedProfile!;
    final deviceAtRequest = _connectedDevice;
    final operation = ++_autoRestoreOperation;

    if (!backend.requestSetAutoRestore(connectionGeneration, enabled)) {
      setState(() {
        _autoRestoreMessage = 'Unable to request Auto Restore update.';
      });
      return;
    }

    _autoRestoreTimer?.cancel();

    setState(() {
      _updatingAutoRestore = true;
      _autoRestoreMessage = 'Saving Auto Restore preference...';
    });

    var attempts = 0;

    _autoRestoreTimer = Timer.periodic(const Duration(milliseconds: 250), (
      timer,
    ) {
      if (!mounted || operation != _autoRestoreOperation) {
        timer.cancel();
        return;
      }

      attempts++;
      final result = backend.autoRestoreResult;

      if (result == 'PENDING' || result == 'NOT_REQUESTED') {
        if (attempts < 20) return;

        timer.cancel();
        _autoRestoreTimer = null;

        setState(() {
          _updatingAutoRestore = false;
          _autoRestoreMessage = 'Auto Restore update timed out.';
        });
        return;
      }

      timer.cancel();
      _autoRestoreTimer = null;

      if (backend.connectionGeneration != connectionGeneration ||
          _connectedDevice != deviceAtRequest ||
          _savedProfile != profileAtRequest) {
        setState(() {
          _updatingAutoRestore = false;
          _autoRestoreMessage =
              'Device or profile changed. Refreshing saved profile.';
        });
        _requestSavedProfile();
        return;
      }

      final success = result == 'AUTO_RESTORE_UPDATED;$enabled';

      setState(() {
        _updatingAutoRestore = false;
        _autoRestoreMessage = success
            ? 'Auto Restore preference saved.'
            : 'Auto Restore update failed: $result';
      });

      if (success) {
        _requestSavedProfile();
      }
    });
  }

  void _selectCodec(int? codec) {
    if (codec == null) return;

    final capability = _codecSnapshot?.capabilityFor(codec);
    if (capability == null) return;

    final rates = capability.availableSampleRates;
    final depths = capability.availableBitDepths;

    setState(() {
      _codecSelectionDirty = true;
      _selectedCodec = codec;
      _selectedSampleRate = rates.isNotEmpty ? rates.first : null;
      _selectedBitDepth = depths.isNotEmpty ? depths.first : null;
      _selectedLdacQuality =
          codec == 4 &&
              _codecSnapshot?.codec == 4 &&
              AudioLdacQuality.isKnown(_codecSnapshot?.codecSpecific1)
          ? _codecSnapshot?.codecSpecific1
          : null;
    });
  }

  Widget _buildCodecSelectors() {
    final snapshot = _codecSnapshot;

    if (snapshot == null || snapshot.capabilities.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          'Codec options will appear when Android provides '
          'the selectable capabilities.',
        ),
      );
    }

    final unique = <int, AudioCodecCapability>{};

    for (final capability in snapshot.capabilities) {
      if (capability.availableSampleRates.isNotEmpty &&
          capability.availableBitDepths.isNotEmpty) {
        unique.putIfAbsent(capability.codec, () => capability);
      }
    }

    final capabilities = unique.values.toList();

    final selectedCapability = _selectedCodec == null
        ? null
        : unique[_selectedCodec];

    final rates = selectedCapability?.availableSampleRates ?? <int>[];
    final depths = selectedCapability?.availableBitDepths ?? <int>[];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<int>(
            key: ValueKey('codec-$_selectedCodec'),
            initialValue: unique.containsKey(_selectedCodec)
                ? _selectedCodec
                : null,
            decoration: const InputDecoration(
              labelText: 'Codec',
              border: OutlineInputBorder(),
            ),
            items: capabilities.map((capability) {
              return DropdownMenuItem<int>(
                value: capability.codec,
                child: Text(capability.name),
              );
            }).toList(),
            onChanged: capabilities.isEmpty ? null : _selectCodec,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: ValueKey('rate-$_selectedCodec-$_selectedSampleRate'),
            initialValue: rates.contains(_selectedSampleRate)
                ? _selectedSampleRate
                : null,
            decoration: const InputDecoration(
              labelText: 'Sample rate',
              border: OutlineInputBorder(),
            ),
            items: rates.map((rate) {
              return DropdownMenuItem<int>(
                value: rate,
                child: Text(
                  AudioCodecCapability.sampleRateNames[rate] ?? '$rate',
                ),
              );
            }).toList(),
            onChanged: rates.isEmpty
                ? null
                : (value) {
                    setState(() {
                      _selectedSampleRate = value;
                      _codecSelectionDirty = true;
                    });
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: ValueKey('bits-$_selectedCodec-$_selectedBitDepth'),
            initialValue: depths.contains(_selectedBitDepth)
                ? _selectedBitDepth
                : null,
            decoration: const InputDecoration(
              labelText: 'Bit depth',
              border: OutlineInputBorder(),
            ),
            items: depths.map((bits) {
              return DropdownMenuItem<int>(
                value: bits,
                child: Text(
                  AudioCodecCapability.bitDepthNames[bits] ?? '$bits',
                ),
              );
            }).toList(),
            onChanged: depths.isEmpty
                ? null
                : (value) {
                    setState(() {
                      _selectedBitDepth = value;
                      _codecSelectionDirty = true;
                    });
                  },
          ),
          const SizedBox(height: 12),
          if (_selectedCodec == 4) ...[
            DropdownButtonFormField<int>(
              key: ValueKey('ldac-$_selectedLdacQuality'),
              initialValue: AudioLdacQuality.isKnown(_selectedLdacQuality)
                  ? _selectedLdacQuality
                  : null,
              decoration: const InputDecoration(
                labelText: 'LDAC quality',
                border: OutlineInputBorder(),
              ),
              items: AudioLdacQuality.names.entries.map((entry) {
                return DropdownMenuItem<int>(
                  value: entry.key,
                  child: Text(entry.value),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedLdacQuality = value;
                  _codecSelectionDirty = true;
                });
              },
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed:
                _applyingCodec ||
                    _savingProfile ||
                    _deletingProfile ||
                    _selectedCodec == null ||
                    _selectedSampleRate == null ||
                    _selectedBitDepth == null
                ? null
                : _applyCodecSelection,
            icon: _applyingCodec
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(_applyingCodec ? 'Applying...' : 'Apply'),
          ),
          if (_applyMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_applyMessage, textAlign: TextAlign.center),
          ],
          if (_verifiedCodec == 4 &&
              _verifiedLdacQuality != null &&
              _verifiedConnectionGeneration ==
                  AudioBackend.instance.connectionGeneration &&
              AudioLdacQuality.isKnown(_verifiedLdacQuality)) ...[
            const SizedBox(height: 8),
            Text(
              'Verified LDAC quality: '
              '${AudioLdacQuality.names[_verifiedLdacQuality]}',
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed:
                _applyingCodec ||
                    _savingProfile ||
                    _deletingProfile ||
                    _selectedCodec == null ||
                    _selectedSampleRate == null ||
                    _selectedBitDepth == null ||
                    _selectedCodec != _verifiedCodec ||
                    _selectedSampleRate != _verifiedSampleRate ||
                    _selectedBitDepth != _verifiedBitDepth ||
                    (_selectedCodec == 4 &&
                        _selectedLdacQuality != _verifiedLdacQuality) ||
                    _verifiedConnectionGeneration == null ||
                    _verifiedConnectionGeneration !=
                        AudioBackend.instance.connectionGeneration
                ? null
                : _saveCodecProfile,
            icon: _savingProfile
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bookmark_add_outlined),
            label: Text(_savingProfile ? 'Saving...' : 'Save profile'),
          ),
          if (_saveProfileMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_saveProfileMessage, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }

  void _requestPermission() {
    final backend = AudioBackend.instance;
    final generation = backend.permissionGeneration;

    if (generation < 0) {
      _showPermissionError();
      return;
    }

    if (!backend.requestBluetoothPermission()) {
      _showPermissionError();
      return;
    }

    _permissionTimer?.cancel();
    var attempts = 0;

    _permissionTimer = Timer.periodic(const Duration(milliseconds: 250), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      attempts++;

      final currentGeneration = backend.permissionGeneration;

      if (currentGeneration != generation && currentGeneration >= 0) {
        timer.cancel();
        _permissionTimer = null;
        _refresh();
      } else if (attempts >= 120) {
        timer.cancel();
        _permissionTimer = null;
        _refresh();
      }
    });
    setState(() {});
  }

  void _showPermissionError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unable to request Bluetooth permission.')),
    );
  }

  String get _companionStatusLabel {
    return switch (_companionStatus) {
      'ASSOCIATED' => 'Device authorized',
      'NOT_ASSOCIATED' => 'Device authorization required',
      'PENDING' => 'Checking device authorization...',
      'NOT_REQUESTED' => 'Waiting for a connected device',
      'DEVICE_UNAVAILABLE' => 'No audio device available',
      'PERMISSION_REQUIRED' => 'Bluetooth permission required',
      'CDM_UNAVAILABLE' => 'Android companion service unavailable',
      'ACTIVITY_UNAVAILABLE' => 'Activity unavailable',
      'TIMEOUT' => 'Authorization check timed out',
      'BACKEND_UNAVAILABLE' => 'Authorization backend unavailable',
      'BACKEND_ERROR' => 'Authorization backend error',
      'CDM_ERROR' => 'Android companion service error',
      final other => 'Authorization status: $other',
    };
  }

  String get _statusLabel {
    return switch (_status) {
      AudioBluetoothStatus.unavailable =>
        'Bluetooth unavailable or backend not ready',
      AudioBluetoothStatus.disabled => 'Bluetooth is turned off',
      AudioBluetoothStatus.permissionRequired =>
        'Bluetooth permission required',
      AudioBluetoothStatus.enabled => 'Bluetooth is enabled',
    };
  }

  IconData get _statusIcon {
    return switch (_status) {
      AudioBluetoothStatus.unavailable => Icons.bluetooth_disabled_rounded,
      AudioBluetoothStatus.disabled => Icons.bluetooth_disabled_rounded,
      AudioBluetoothStatus.permissionRequired => Icons.lock_outline_rounded,
      AudioBluetoothStatus.enabled => Icons.bluetooth_connected_rounded,
    };
  }

  @override
  void dispose() {
    AudioBackend.instance.cancelPendingApply();
    _permissionTimer?.cancel();
    _deviceTimer?.cancel();
    _codecTimer?.cancel();
    _postConnectCodecTimer?.cancel();
    _connectionWatchTimer?.cancel();
    _companionTimer?.cancel();
    _companionAssociationTimer?.cancel();
    _applyTimer?.cancel();
    _verifyTimer?.cancel();
    _profileTimer?.cancel();
    _saveProfileTimer?.cancel();
    _autoRestoreTimer?.cancel();
    _autoRestoreOperation++;
    _deleteProfileTimer?.cancel();
    _deleteProfileOperation++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Audio Hub'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack,
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh Bluetooth status',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            Icon(Icons.headphones_rounded, size: 48, color: colors.primary),
            const SizedBox(height: 20),
            Text(
              'Bluetooth Audio',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Manage Bluetooth audio devices and codec preferences.',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: Icon(_statusIcon),
                title: const Text('Bluetooth status'),
                subtitle: Text(_statusLabel),
                trailing: IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _refresh,
                ),
              ),
            ),
            if (_status == AudioBluetoothStatus.permissionRequired) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _permissionTimer == null ? _requestPermission : null,
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('Grant Bluetooth Permission'),
              ),
            ],
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.bluetooth_audio_rounded),
                title: const Text('Connected device'),
                subtitle: Text(
                  _deviceLoading
                      ? 'Detecting Bluetooth audio device...'
                      : _connectedDevice.isNotEmpty
                      ? _connectedDevice
                      : 'No connected A2DP device detected',
                ),
              ),
            ),
            if (_connectedDevice.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: Icon(
                    _companionStatus == 'ASSOCIATED'
                        ? Icons.verified_user_outlined
                        : Icons.shield_outlined,
                  ),
                  title: const Text('Device authorization'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_companionStatusLabel),
                      if (_associatingCompanion) ...[
                        const SizedBox(height: 6),
                        const Text('Authorization in progress...'),
                      ] else if (_companionAssociationResult !=
                          'NOT_REQUESTED') ...[
                        const SizedBox(height: 6),
                        Text(
                          'Authorization result: '
                          '$_companionAssociationResult',
                        ),
                      ],
                      if (_companionStatus == 'NOT_ASSOCIATED' &&
                          !_associatingCompanion) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _requestCompanionAssociation,
                          icon: const Icon(Icons.verified_user_outlined),
                          label: const Text('Authorize device'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    leading: const Icon(Icons.tune_rounded),
                    title: const Text('Codec configuration'),
                    subtitle: Text(_codecDiagnosticLabel),
                  ),
                  _buildCodecSelectors(),
                ],
              ),
            ),
            if (_connectedDevice.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildSavedProfileCard(),
            ],
            const SizedBox(height: 24),
            _buildExternalLinkCard(
              icon: Icons.code_rounded,
              title: 'GitHub Repository',
              subtitle: 'EricDark231',
              linkCode: 2,
            ),
            const SizedBox(height: 8),
            _buildExternalLinkCard(
              icon: Icons.send_rounded,
              title: 'Telegram',
              subtitle: '@EricDark231',
              linkCode: 3,
            ),
            const SizedBox(height: 20),
            Center(
              child: Column(
                children: [
                  Text(
                    '❧',
                    style: TextStyle(
                      fontSize: 22,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Made with passion, born from necessity, '
                    'and rooted in the heart.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExternalLinkCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required int linkCode,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          final opened = RodinBackend.instance.openSupportLink(linkCode);
          if (!opened && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Unable to open link.')),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: colors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(color: colors.primary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_outward_rounded,
                color: colors.primary,
                size: 19,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
