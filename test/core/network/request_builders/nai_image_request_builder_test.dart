import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_launcher/core/constants/api_constants.dart';
import 'package:nai_launcher/core/enums/precise_ref_type.dart';
import 'package:nai_launcher/core/network/request_builders/nai_image_request_builder.dart';
import 'package:nai_launcher/core/utils/nai_api_utils.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/data/models/vibe/vibe_reference.dart';

void main() {
  group('NAIImageRequestBuilder.build', () {
    test('should keep provided sampler and stream mode difference', () async {
      const params = ImageParams(model: 'nai-diffusion-4-full');
      final builder = NAIImageRequestBuilder(
        params: params,
        encodeVibe: _fakeEncodeVibe,
      );

      final nonStreamResult = await builder.build(sampler: 'mapped_sampler');
      expect(nonStreamResult.requestParameters['sampler'], 'mapped_sampler');
      expect(nonStreamResult.requestParameters.containsKey('stream'), isFalse);

      final streamResult = await builder.build(
        sampler: 'raw_stream_sampler',
        isStream: true,
      );
      expect(streamResult.requestParameters['sampler'], 'raw_stream_sampler');
      expect(streamResult.requestParameters['stream'], 'msgpack');
    });

    test('should send effective prompt while forwarding native preset flags',
        () async {
      final params = ImageParams(
        prompt: '1girl, sunset',
        negativePrompt: 'bad hands',
        model: ImageModels.animeDiffusionV45Full,
        qualityToggle: true,
        ucPreset: UcPresets.toApiValue(UcPresetType.heavy),
      );
      final builder = NAIImageRequestBuilder(
        params: params,
        encodeVibe: _fakeEncodeVibe,
      );

      final result = await builder.build(sampler: 'k_euler');
      final parameters = result.requestParameters;
      final preset = UcPresets.getPresetContent(
        ImageModels.animeDiffusionV45Full,
        UcPresetType.heavy,
      );

      expect(
        result.requestData['input'],
        equals('1girl, sunset, location, very aesthetic, masterpiece, no text'),
      );
      expect(parameters['negative_prompt'], equals('$preset, bad hands'));
      expect(parameters['qualityToggle'], isTrue);
      expect(parameters['ucPreset'], equals(0));
      expect(
        parameters['v4_prompt']['caption']['base_caption'],
        equals('1girl, sunset, location, very aesthetic, masterpiece, no text'),
      );
      expect(
        parameters['v4_negative_prompt']['caption']['base_caption'],
        equals('$preset, bad hands'),
      );
    });

    test('should throw ArgumentError when sampler is empty', () async {
      const params = ImageParams();
      final builder = NAIImageRequestBuilder(
        params: params,
        encodeVibe: _fakeEncodeVibe,
      );

      expect(
        () => builder.build(sampler: ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should apply native quality and UC presets only at request boundary',
        () async {
      final params = ImageParams(
        prompt: 'fixed positive, user positive',
        negativePrompt: 'fixed negative, user negative',
        model: ImageModels.animeDiffusionV45Full,
        qualityToggle: true,
        ucPreset: UcPresets.toApiValue(UcPresetType.heavy),
      );
      final builder = NAIImageRequestBuilder(
        params: params,
        encodeVibe: _fakeEncodeVibe,
      );

      final result = await builder.build(sampler: 'k_euler');
      final preset = UcPresets.getPresetContent(
        ImageModels.animeDiffusionV45Full,
        UcPresetType.heavy,
      );

      expect(
        result.effectivePrompt,
        equals(
          'fixed positive, user positive, location, very aesthetic, masterpiece, no text',
        ),
      );
      expect(
        result.effectiveNegativePrompt,
        equals('$preset, fixed negative, user negative'),
      );
      expect(result.requestData['input'], equals(result.effectivePrompt));
      expect(
        result.requestParameters['negative_prompt'],
        equals(result.effectiveNegativePrompt),
      );
      expect(result.requestParameters['ucPreset'], equals(0));
      expect(result.effectiveNegativePrompt, isNot(contains('nsfw')));
    });

    test('should return vibeEncodingMap only in non-stream mode', () async {
      final params = ImageParams(
        model: 'nai-diffusion-4-full',
        vibeReferencesV4: [
          VibeReference(
            displayName: 'raw',
            vibeEncoding: '',
            rawImageData: Uint8List.fromList([1, 2, 3]),
            sourceType: VibeSourceType.rawImage,
          ),
          const VibeReference(
            displayName: 'pre',
            vibeEncoding: 'pre-encoded',
            sourceType: VibeSourceType.png,
          ),
        ],
      );

      final builder = NAIImageRequestBuilder(
        params: params,
        encodeVibe: _fakeEncodeVibe,
      );

      final nonStreamResult =
          await builder.build(sampler: 'sampler_non_stream');
      expect(nonStreamResult.vibeEncodingMap, {
        0: 'encoded-vibe',
        1: 'pre-encoded',
      });

      final streamResult = await builder.build(
        sampler: 'sampler_stream',
        isStream: true,
      );
      expect(streamResult.vibeEncodingMap, isEmpty);
    });

    test('should ignore precise references for non-v4.5 model', () async {
      final params = ImageParams(
        model: 'nai-diffusion-4-full',
        preciseReferences: [
          PreciseReference(
            image: _validPngBytes(),
            type: PreciseRefType.character,
          ),
        ],
      );

      final builder = NAIImageRequestBuilder(
        params: params,
        encodeVibe: _fakeEncodeVibe,
      );

      final result = await builder.build(sampler: 'ddim_v3');
      expect(
        result.requestParameters.containsKey('director_reference_images'),
        isFalse,
      );
    });

    test('should include precise references for v4.5 model', () async {
      final params = ImageParams(
        model: 'nai-diffusion-4-5-full',
        preciseReferences: [
          PreciseReference(
            image: _validPngBytes(),
            type: PreciseRefType.character,
          ),
        ],
      );

      final builder = NAIImageRequestBuilder(
        params: params,
        encodeVibe: _fakeEncodeVibe,
      );

      final result = await builder.build(sampler: 'k_euler');
      expect(
        result.requestParameters.containsKey('director_reference_images'),
        isTrue,
      );
    });

    test('should reuse normalized precise reference image without reprocessing',
        () async {
      final normalizedBytes =
          NAIApiUtils.markNormalizedPreciseReferencePng(_validPngBytes());
      final params = ImageParams(
        model: 'nai-diffusion-4-5-full',
        preciseReferences: [
          PreciseReference(
            image: normalizedBytes,
            type: PreciseRefType.character,
          ),
        ],
      );

      final builder = NAIImageRequestBuilder(
        params: params,
        encodeVibe: _fakeEncodeVibe,
      );

      final result = await builder.build(sampler: 'k_euler');
      final encodedImages =
          result.requestParameters['director_reference_images'] as List;

      expect(base64Decode(encodedImages.single as String), normalizedBytes);
    });

    test('should normalize precise reference images off the caller isolate',
        () async {
      final normalizedBytes = await NAIApiUtils.ensurePngFormatAsync(
        _validPngBytes(width: 8, height: 4),
      );
      final decoded = img.decodeImage(normalizedBytes);

      expect(decoded, isNotNull);
      expect('${decoded!.width}x${decoded.height}', '1024x1536');
      expect(
        NAIApiUtils.isKnownNormalizedPreciseReferencePng(normalizedBytes),
        isTrue,
      );
    });

    test('should forward infill strength and noise to request parameters',
        () async {
      final params = ImageParams(
        action: ImageGenerationAction.infill,
        model: 'nai-diffusion-4-full',
        sourceImage: Uint8List.fromList([1, 2, 3]),
        maskImage: Uint8List.fromList([4, 5, 6]),
        strength: 0.42,
        noise: 0.13,
        inpaintStrength: 0.55,
      );

      final builder = NAIImageRequestBuilder(
        params: params,
        encodeVibe: _fakeEncodeVibe,
      );

      final result = await builder.build(sampler: 'k_euler');

      expect(result.requestParameters['strength'], equals(0.42));
      expect(result.requestParameters['noise'], equals(0.13));
      expect(result.requestParameters['inpaintImg2ImgStrength'], equals(0.55));
      expect(result.requestParameters['mask'], isNotNull);
    });

    test('should omit vibe transfer payload for infill requests', () async {
      final params = ImageParams(
        action: ImageGenerationAction.infill,
        model: 'nai-diffusion-4-full-inpainting',
        sourceImage: Uint8List.fromList([1, 2, 3]),
        maskImage: Uint8List.fromList([4, 5, 6]),
        vibeReferencesV4: const [
          VibeReference(
            displayName: 'pre',
            vibeEncoding: 'pre-encoded',
            sourceType: VibeSourceType.png,
          ),
        ],
      );

      final builder = NAIImageRequestBuilder(
        params: params,
        encodeVibe: _fakeEncodeVibe,
      );

      final nonStreamResult = await builder.build(sampler: 'k_euler');
      expect(
        nonStreamResult.requestParameters
            .containsKey('reference_image_multiple'),
        isFalse,
      );
      expect(nonStreamResult.vibeEncodingMap, isEmpty);

      final streamResult = await builder.build(
        sampler: 'k_euler',
        isStream: true,
      );
      expect(
        streamResult.requestParameters.containsKey('reference_image_multiple'),
        isFalse,
      );
      expect(streamResult.vibeEncodingMap, isEmpty);
    });

    test(
        'should normalize infill mask to hard binary edges and disable overlay original image',
        () async {
      final noisyMask = img.Image(width: 16, height: 16);
      img.fill(noisyMask, color: img.ColorRgba8(0, 0, 0, 255));
      for (var y = 10; y <= 13; y++) {
        for (var x = 10; x <= 13; x++) {
          noisyMask.setPixelRgba(x, y, 90, 160, 255, 120);
        }
      }

      final params = ImageParams(
        action: ImageGenerationAction.infill,
        model: 'nai-diffusion-4-5-full',
        sourceImage: _validPngBytes(),
        maskImage: Uint8List.fromList(img.encodePng(noisyMask)),
        addOriginalImage: true,
      );

      final builder = NAIImageRequestBuilder(
        params: params,
        encodeVibe: _fakeEncodeVibe,
      );

      final result = await builder.build(sampler: 'k_euler');
      final maskBytes =
          base64Decode(result.requestParameters['mask'] as String);
      final decodedMask = img.decodeImage(maskBytes)!;

      expect(result.requestParameters['add_original_image'], isFalse);
      expect(decodedMask.getPixel(0, 0).r.toInt(), equals(0));
      expect(decodedMask.getPixel(0, 0).a.toInt(), equals(255));
      expect(decodedMask.getPixel(8, 8).r.toInt(), equals(255));
      expect(decodedMask.getPixel(15, 15).r.toInt(), equals(255));
      expect(decodedMask.getPixel(8, 8).a.toInt(), equals(255));
      expect(decodedMask.getPixel(7, 7).r.toInt(), equals(0));
    });

    test('should allow focused inpaint masks to skip extra post expansion',
        () async {
      final singlePixelMask = img.Image(width: 16, height: 16);
      img.fill(singlePixelMask, color: img.ColorRgba8(0, 0, 0, 255));
      for (var y = 10; y <= 13; y++) {
        for (var x = 10; x <= 13; x++) {
          singlePixelMask.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      }

      final params = ImageParams(
        action: ImageGenerationAction.infill,
        model: 'nai-diffusion-4-5-full',
        sourceImage: _validPngBytes(),
        maskImage: Uint8List.fromList(img.encodePng(singlePixelMask)),
        inpaintMaskClosingIterations: 0,
        inpaintMaskExpansionIterations: 0,
      );

      final builder = NAIImageRequestBuilder(
        params: params,
        encodeVibe: _fakeEncodeVibe,
      );

      final result = await builder.build(sampler: 'k_euler');
      final maskBytes =
          base64Decode(result.requestParameters['mask'] as String);
      final decodedMask = img.decodeImage(maskBytes)!;

      expect(decodedMask.getPixel(8, 8).r.toInt(), equals(255));
      expect(decodedMask.getPixel(15, 15).r.toInt(), equals(255));
      expect(decodedMask.getPixel(7, 8).r.toInt(), equals(0));
      expect(decodedMask.getPixel(8, 7).r.toInt(), equals(0));
    });

    test('should prefer precise reference over vibe transfer on v4.5 requests',
        () async {
      final params = ImageParams(
        model: 'nai-diffusion-4-5-full',
        preciseReferences: [
          PreciseReference(
            image: _validPngBytes(),
            type: PreciseRefType.character,
          ),
        ],
        vibeReferencesV4: const [
          VibeReference(
            displayName: 'pre',
            vibeEncoding: 'pre-encoded',
            sourceType: VibeSourceType.png,
          ),
        ],
      );

      final builder = NAIImageRequestBuilder(
        params: params,
        encodeVibe: _fakeEncodeVibe,
      );

      final result = await builder.build(sampler: 'k_euler');
      expect(
        result.requestParameters.containsKey('director_reference_images'),
        isTrue,
      );
      expect(
        result.requestParameters.containsKey('reference_image_multiple'),
        isFalse,
      );
      expect(result.vibeEncodingMap, isEmpty);
    });
  });
}

Future<String> _fakeEncodeVibe(
  Uint8List image, {
  required String model,
  double informationExtracted = 1.0,
}) async {
  return 'encoded-vibe';
}

Uint8List _validPngBytes({
  int width = 2,
  int height = 2,
}) =>
    Uint8List.fromList(
      img.encodePng(img.Image(width: width, height: height)),
    );
