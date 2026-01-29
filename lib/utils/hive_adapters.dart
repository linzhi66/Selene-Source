import 'package:hive/hive.dart';
import 'package:selene/models/favorite_item.dart';
import 'package:selene/models/live_source.dart';
import 'package:selene/models/play_record.dart';
import 'package:selene/models/search_resource.dart';

class FavoriteItemAdapter extends TypeAdapter<FavoriteItem> {
  @override
  final int typeId = 1;

  @override
  void write(BinaryWriter writer, FavoriteItem obj) {
    writer.writeString(obj.source);
    writer.writeString(obj.id);
    writer.writeString(obj.title);
    writer.writeString(obj.sourceName);
    writer.writeString(obj.year);
    writer.writeString(obj.cover);
    writer.writeInt(obj.totalEpisodes);
    writer.writeInt(obj.saveTime);
    writer.writeString(obj.origin);
  }

  @override
  FavoriteItem read(BinaryReader reader) {
    final source = reader.readString();
    final id = reader.readString();
    final title = reader.readString();
    final sourceName = reader.readString();
    final year = reader.readString();
    final cover = reader.readString();
    final totalEpisodes = reader.readInt();
    final saveTime = reader.readInt();
    final origin = reader.readString();

    return FavoriteItem(
      source: source,
      id: id,
      title: title,
      sourceName: sourceName,
      year: year,
      cover: cover,
      totalEpisodes: totalEpisodes,
      saveTime: saveTime,
      origin: origin,
    );
  }
}

class LiveSourceAdapter extends TypeAdapter<LiveSource> {
  @override
  final int typeId = 2;

  @override
  void write(BinaryWriter writer, LiveSource obj) {
    writer.writeString(obj.key);
    writer.writeString(obj.name);
    writer.writeString(obj.url);
    writer.writeString(obj.ua);
    writer.writeString(obj.epg);
    writer.writeString(obj.from);
    writer.writeBool(obj.disabled);
  }

  @override
  LiveSource read(BinaryReader reader) {
    final key = reader.readString();
    final name = reader.readString();
    final url = reader.readString();
    final ua = reader.readString();
    final epg = reader.readString();
    final from = reader.readString();
    final disabled = reader.readBool();

    return LiveSource(
      key: key,
      name: name,
      url: url,
      ua: ua,
      epg: epg,
      from: from,
      disabled: disabled,
    );
  }
}

class PlayRecordAdapter extends TypeAdapter<PlayRecord> {
  @override
  final int typeId = 3;

  @override
  void write(BinaryWriter writer, PlayRecord obj) {
    writer.writeString(obj.source);
    writer.writeString(obj.id);
    writer.writeString(obj.title);
    writer.writeString(obj.sourceName);
    writer.writeString(obj.year);
    writer.writeString(obj.cover);
    writer.writeInt(obj.index);
    writer.writeInt(obj.totalEpisodes);
    writer.writeInt(obj.playTime);
    writer.writeInt(obj.totalTime);
    writer.writeInt(obj.saveTime);
    writer.writeString(obj.searchTitle);
  }

  @override
  PlayRecord read(BinaryReader reader) {
    final source = reader.readString();
    final id = reader.readString();
    final title = reader.readString();
    final sourceName = reader.readString();
    final year = reader.readString();
    final cover = reader.readString();
    final index = reader.readInt();
    final totalEpisodes = reader.readInt();
    final playTime = reader.readInt();
    final totalTime = reader.readInt();
    final saveTime = reader.readInt();
    final searchTitle = reader.readString();

    return PlayRecord(
      source: source,
      id: id,
      title: title,
      sourceName: sourceName,
      year: year,
      cover: cover,
      index: index,
      totalEpisodes: totalEpisodes,
      playTime: playTime,
      totalTime: totalTime,
      saveTime: saveTime,
      searchTitle: searchTitle,
    );
  }
}

class SearchResourceAdapter extends TypeAdapter<SearchResource> {
  @override
  final int typeId = 4;

  @override
  void write(BinaryWriter writer, SearchResource obj) {
    writer.writeString(obj.key);
    writer.writeString(obj.name);
    writer.writeString(obj.api);
    writer.writeString(obj.detail);
    writer.writeString(obj.from);
    writer.writeBool(obj.disabled);
  }

  @override
  SearchResource read(BinaryReader reader) {
    final key = reader.readString();
    final name = reader.readString();
    final api = reader.readString();
    final detail = reader.readString();
    final from = reader.readString();
    final disabled = reader.readBool();

    return SearchResource(
      key: key,
      name: name,
      api: api,
      detail: detail,
      from: from,
      disabled: disabled,
    );
  }
}
