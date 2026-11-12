import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/student_report_service.dart';
import '../cubit/student_report_create_cubit.dart';
import '../cubit/student_report_create_state.dart';
import '../student_navigation.dart';
import '../widgets/student_ui.dart';

class StudentReportCreatePage extends StatelessWidget {
  const StudentReportCreatePage({this.cubit, this.service, super.key});

  final StudentReportCreateCubit? cubit;
  final StudentReportService? service;

  @override
  Widget build(BuildContext context) {
    if (cubit != null) {
      return BlocProvider.value(
        value: cubit!,
        child: const _StudentReportCreateView(),
      );
    }
    return BlocProvider(
      create: (_) =>
          StudentReportCreateCubit(service ?? StudentReportService())..load(),
      child: const _StudentReportCreateView(),
    );
  }
}

class _StudentReportCreateView extends StatelessWidget {
  const _StudentReportCreateView();

  static const categories = <String, String>{
    'asset_damage': 'Kerusakan aset',
    'asset_lost': 'Aset hilang',
    'network': 'Masalah Jaringan',
    'computer': 'Komputer',
    'software': 'Software',
    'facility': 'Fasilitas',
    'electricity': 'Kelistrikan',
    'other': 'Lainnya',
  };

  @override
  Widget build(BuildContext context) {
    return BlocListener<StudentReportCreateCubit, StudentReportCreateState>(
      listenWhen: (previous, current) => previous.status != current.status,
      listener: (context, state) {
        if (state.status == StudentReportCreateStatus.success &&
            state.reportId != null) {
          openCreatedStudentReport(context, state.reportId!);
        }
      },
      child: Scaffold(
        backgroundColor: studentPaper,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child:
              BlocBuilder<StudentReportCreateCubit, StudentReportCreateState>(
                builder: (context, state) {
                  if (state.status == StudentReportCreateStatus.loading &&
                      state.laboratories.isEmpty) {
                    return const StudentLoading(
                      message: 'Memuat laboratorium.',
                    );
                  }
                  if (state.status == StudentReportCreateStatus.failure &&
                      state.laboratories.isEmpty) {
                    return StudentErrorState(
                      message: state.errorMessage,
                      onRetry: context.read<StudentReportCreateCubit>().load,
                    );
                  }
                  return _form(context, state);
                },
              ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context, StudentReportCreateState state) {
    final cubit = context.read<StudentReportCreateCubit>();
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
      children: [
        StudentBackHeader(
          title: 'Buat Laporan',
          onBack: () => studentPopOrGo(context, '/student/reports'),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: state.category,
          decoration: _decoration('Kategori'),
          items: categories.entries
              .map(
                (entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) cubit.setCategory(value);
          },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: state.labId.isEmpty ? null : state.labId,
          decoration: _decoration('Laboratorium'),
          items: state.laboratories
              .map(
                (lab) => DropdownMenuItem(
                  value: lab.id,
                  child: Text(lab.name, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: state.status == StudentReportCreateStatus.saving
              ? null
              : (value) {
                  if (value != null) cubit.selectLaboratory(value);
                },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: state.assetId,
          decoration: _decoration('Aset (opsional)'),
          items: [
            const DropdownMenuItem<String>(
              value: null,
              child: Text('Tidak terkait aset', overflow: TextOverflow.ellipsis),
            ),
            ...state.assets.map(
              (asset) => DropdownMenuItem(
                value: asset.id,
                child: Text(
                  '${asset.name} · ${asset.code}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: cubit.setAsset,
        ),
        const SizedBox(height: 10),
        TextField(
          maxLength: 120,
          onChanged: cubit.setTitle,
          decoration: _decoration('Judul')
              .copyWith(hintText: 'Jaringan Tidak Tersambung', counterText: ''),
        ),
        const SizedBox(height: 10),
        TextField(
          minLines: 4,
          maxLines: 7,
          maxLength: 2000,
          onChanged: cubit.setDescription,
          decoration: _decoration('Deskripsi').copyWith(
            hintText: 'Jelaskan masalah dan kapan terjadi',
            counterText: '',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          maxLength: 160,
          onChanged: cubit.setLocation,
          decoration: _decoration('Lokasi')
              .copyWith(hintText: 'Contoh: Lab IoT, meja 3', counterText: ''),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: state.severity,
          decoration: _decoration('Urgensi'),
          items: const [
            DropdownMenuItem(
              value: 'normal',
              child: Text('Normal', overflow: TextOverflow.ellipsis),
            ),
            DropdownMenuItem(
              value: 'urgent',
              child: Text('Mendesak', overflow: TextOverflow.ellipsis),
            ),
          ],
          onChanged: (value) {
            if (value != null) cubit.setSeverity(value);
          },
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(color: studentBorder, style: BorderStyle.solid),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            children: [
              Icon(Icons.image_not_supported_outlined, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Lampiran foto belum tersedia pada versi ini.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: studentMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (state.errorMessage.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            state.errorMessage,
            style: const TextStyle(
              color: studentPinkText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 14),
        SizedBox(
          height: 54,
          child: FilledButton.icon(
            onPressed: state.status == StudentReportCreateStatus.saving
                ? null
                : cubit.submit,
            style: FilledButton.styleFrom(
              backgroundColor: studentInk,
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
            ),
            icon: state.status == StudentReportCreateStatus.saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.arrow_forward_rounded),
            label: const Text(
              'Kirim Laporan',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: studentBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: studentBorder),
      ),
    );
  }
}
