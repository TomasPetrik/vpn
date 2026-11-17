import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/update_policy.dart';
import 'app_update_cubit.dart';

class UpdateRequiredPage extends StatelessWidget {
  const UpdateRequiredPage({super.key});

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
                    onPressed: policy.updateUrl.isEmpty
                        ? null
                        : () async {
                            final uri = Uri.tryParse(policy.updateUrl);
                            if (uri != null) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
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
