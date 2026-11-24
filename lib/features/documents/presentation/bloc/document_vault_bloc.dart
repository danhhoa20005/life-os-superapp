import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/utils/vietnamese_search_matcher.dart';
import '../../domain/entities/document_vault_entity.dart';
import '../../domain/repositories/document_vault_repository.dart';

sealed class DocumentVaultEvent extends Equatable {
  const DocumentVaultEvent();

  @override
  List<Object?> get props => [];
}

final class DocumentVaultWatchStarted extends DocumentVaultEvent {
  final String userId;
  final String? familyId;

  const DocumentVaultWatchStarted({required this.userId, this.familyId});

  @override
  List<Object?> get props => [userId, familyId];
}

final class DocumentVaultFolderFilterChanged extends DocumentVaultEvent {
  final DocumentFolderCategory? folder;

  const DocumentVaultFolderFilterChanged(this.folder);

  @override
  List<Object?> get props => [folder];
}

final class DocumentVaultSearchQueryChanged extends DocumentVaultEvent {
  final String query;

  const DocumentVaultSearchQueryChanged(this.query);

  @override
  List<Object?> get props => [query];
}

final class DocumentVaultFiltersCleared extends DocumentVaultEvent {
  const DocumentVaultFiltersCleared();
}

final class DocumentVaultCreateSubmitted extends DocumentVaultEvent {
  final CreateDocumentVaultParams params;

  const DocumentVaultCreateSubmitted(this.params);

  @override
  List<Object?> get props => [params];
}

final class DocumentVaultDeleteRequested extends DocumentVaultEvent {
  final String userId;
  final DocumentVaultEntity document;

  const DocumentVaultDeleteRequested({
    required this.userId,
    required this.document,
  });

  @override
  List<Object?> get props => [userId, document];
}

final class DocumentVaultState extends Equatable {
  final bool isLoading;
  final List<DocumentVaultEntity> documents;
  final DocumentFolderCategory? selectedFolder;
  final String searchQuery;
  final Failure? failure;
  final String? message;

  const DocumentVaultState({
    this.isLoading = false,
    this.documents = const [],
    this.selectedFolder,
    this.searchQuery = '',
    this.failure,
    this.message,
  });

  bool get hasActiveFilters =>
      selectedFolder != null || searchQuery.trim().isNotEmpty;

  int countForFolder(DocumentFolderCategory folder) {
    return documents.where((d) => d.folder == folder).length;
  }

  List<DocumentVaultEntity> get visibleDocuments {
    final q = searchQuery.trim();
    final dateFmt = DateFormat('dd/MM/yyyy');
    return documents.where((doc) {
      if (selectedFolder != null && doc.folder != selectedFolder) return false;
      if (q.isEmpty) return true;
      return VietnameseSearchMatcher.matchesAny(q, [
        doc.title,
        doc.referenceCode,
        doc.note,
        doc.folder.displayTitle,
        doc.uploadedByName,
        doc.expiryDate != null ? dateFmt.format(doc.expiryDate!) : null,
      ]);
    }).toList();
  }

  DocumentVaultState copyWith({
    bool? isLoading,
    List<DocumentVaultEntity>? documents,
    DocumentFolderCategory? selectedFolder,
    bool clearSelectedFolder = false,
    String? searchQuery,
    Failure? failure,
    bool clearFailure = false,
    String? message,
    bool clearMessage = false,
  }) {
    return DocumentVaultState(
      isLoading: isLoading ?? this.isLoading,
      documents: documents ?? this.documents,
      selectedFolder: clearSelectedFolder
          ? null
          : (selectedFolder ?? this.selectedFolder),
      searchQuery: searchQuery ?? this.searchQuery,
      failure: clearFailure ? null : (failure ?? this.failure),
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  @override
  List<Object?> get props => [
    isLoading,
    documents,
    selectedFolder,
    searchQuery,
    failure,
    message,
  ];
}

class DocumentVaultBloc extends Bloc<DocumentVaultEvent, DocumentVaultState> {
  final DocumentVaultRepository _repository;

  DocumentVaultBloc({required DocumentVaultRepository repository})
    : _repository = repository,
      super(const DocumentVaultState()) {
    on<DocumentVaultWatchStarted>(_onWatchStarted, transformer: restartable());
    on<DocumentVaultFolderFilterChanged>(_onFolderChanged);
    on<DocumentVaultSearchQueryChanged>(_onSearchChanged);
    on<DocumentVaultFiltersCleared>(_onFiltersCleared);
    on<DocumentVaultCreateSubmitted>(
      _onCreateSubmitted,
      transformer: droppable(),
    );
    on<DocumentVaultDeleteRequested>(
      _onDeleteRequested,
      transformer: sequential(),
    );
  }

  Future<void> _onWatchStarted(
    DocumentVaultWatchStarted event,
    Emitter<DocumentVaultState> emit,
  ) async {
    emit(
      state.copyWith(isLoading: true, clearFailure: true, clearMessage: true),
    );
    await emit.forEach<List<DocumentVaultEntity>>(
      _repository.watchDocuments(
        userId: event.userId,
        familyId: event.familyId,
      ),
      onData: (docs) => state.copyWith(
        isLoading: false,
        documents: docs,
        clearFailure: true,
        clearMessage: true,
      ),
      onError: (err, _) => state.copyWith(
        isLoading: false,
        failure: UnexpectedFailure(message: 'Lỗi tải kho tài liệu: $err'),
        clearMessage: true,
      ),
    );
  }

  void _onFolderChanged(
    DocumentVaultFolderFilterChanged event,
    Emitter<DocumentVaultState> emit,
  ) {
    if (event.folder == null || event.folder == state.selectedFolder) {
      emit(state.copyWith(clearSelectedFolder: true));
    } else {
      emit(state.copyWith(selectedFolder: event.folder));
    }
  }

  void _onSearchChanged(
    DocumentVaultSearchQueryChanged event,
    Emitter<DocumentVaultState> emit,
  ) {
    emit(state.copyWith(searchQuery: event.query));
  }

  void _onFiltersCleared(
    DocumentVaultFiltersCleared event,
    Emitter<DocumentVaultState> emit,
  ) {
    emit(state.copyWith(clearSelectedFolder: true, searchQuery: ''));
  }

  Future<void> _onCreateSubmitted(
    DocumentVaultCreateSubmitted event,
    Emitter<DocumentVaultState> emit,
  ) async {
    emit(state.copyWith(clearFailure: true, clearMessage: true));
    final res = await _repository.createDocument(event.params);
    res.fold(
      (f) => emit(state.copyWith(failure: f, clearMessage: true)),
      (doc) => emit(
        state.copyWith(
          message: 'Đã lưu "${doc.title}" vào ${doc.folder.displayTitle}.',
        ),
      ),
    );
  }

  Future<void> _onDeleteRequested(
    DocumentVaultDeleteRequested event,
    Emitter<DocumentVaultState> emit,
  ) async {
    emit(state.copyWith(clearFailure: true, clearMessage: true));
    final res = await _repository.deleteDocument(
      userId: event.userId,
      document: event.document,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f, clearMessage: true)),
      (_) => emit(state.copyWith(message: 'Đã xóa "${event.document.title}".')),
    );
  }
}
