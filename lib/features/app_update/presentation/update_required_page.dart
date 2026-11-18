import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/app_store_links.dart';
import '../domain/update_policy.dart';
import 'app_update_cubit.dart';

class UpdateRequiredPage extends StatelessWidget {
  const UpdateRequiredPage({super.key});

  Future<void> _openUpdate(BuildContext context, String policyUrl) async {
    final uri = AppStoreLinks.uriFor(
      policyUrl: policyUrl,
      isIos: defaultTargetPlatform == TargetPlatform.iOS,
    );
    if (uri == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Update link is missing')),
        );
      }
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $uri')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppUpdateCubit, AppUpdateState>(
      builder: (context, state) {
        final policy = state is AppUpdateRequired
            ? state.policy
            : const UpdatePolicy(
                status: UpdateStatus.required,
                minSupportedBuild: 0,
                latestBuild: 0,
                message: 'Please update PetrikVPN to continue.',
              );
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  Text(
                    'Update required',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    policy.message.isEmpty
                        ? 'Please update PetrikVPN to continue.'
                        : policy.message,
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => _openUpdate(context, policy.updateUrl),
                    child: const Text('Update PetrikVPN'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
