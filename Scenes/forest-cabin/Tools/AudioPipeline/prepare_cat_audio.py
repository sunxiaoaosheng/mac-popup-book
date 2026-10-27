#!/usr/bin/env python3
"""Prepare licensed cat recordings as candidates; never replace runtime resources.

Uses only Python's standard library. Original PCM and source hashes are retained.
Numeric checks do not constitute a listening or final character-voice acceptance.
"""
import array
import hashlib
import html
import json
import math
import pathlib
import sys
import wave

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'Assets/AudioSources/Kerzoven'


def read_pcm(path):
    with wave.open(str(path), 'rb') as audio:
        if audio.getnchannels() != 1 or audio.getsampwidth() != 2 or audio.getcomptype() != 'NONE':
            raise ValueError('候选输入必须为单声道16位无损PCM：' + path.name)
        rate = audio.getframerate()
        values = array.array('h', audio.readframes(audio.getnframes()))
    if sys.byteorder != 'little':
        values.byteswap()
    if not values or rate <= 0:
        raise ValueError('空或无效录音：' + path.name)
    return [v / 32768 for v in values], rate


def highpass(values, rate, cutoff):
    coefficient = math.exp(-2 * math.pi * cutoff / rate)
    result, previous_input, previous_output = [], values[0], 0
    for value in values:
        previous_output = coefficient * (previous_output + value - previous_input)
        previous_input = value
        result.append(previous_output)
    return result


def loop_crossfade(values, length):
    if length <= 1 or len(values) <= 3 * length:
        raise ValueError('呼噜长度不足以制作循环')
    head, tail = values[:length], values[-length:]
    blend = [tail[i] * math.cos(i / (length - 1) * math.pi / 2)
             + head[i] * math.sin(i / (length - 1) * math.pi / 2) for i in range(length)]
    return values[length:-length] + blend


def statistics(values, rate):
    peak = max(abs(value) for value in values)
    rms = math.sqrt(sum(value * value for value in values) / len(values))
    return {'duration_seconds': len(values) / rate, 'frames': len(values), 'sample_rate': rate,
            'peak': peak, 'rms': rms, 'dc_offset': sum(values) / len(values),
            'loop_boundary_step': abs(values[-1] - values[0]),
            'clipped_samples': sum(abs(value) >= 1 for value in values)}


def prepare(values, rate, loop):
    # Keep the low purr texture. Meows use a higher cutoff for handling rumble.
    values = highpass(values, rate, 12 if loop else 45)
    if loop:
        # Avoid filter startup and recording endpoints, then make a circular overlap.
        margin = int(rate * .15)
        values = loop_crossfade(values[margin:-margin], int(rate * .12))
    else:
        # Preserve the full utterance rather than guessing an audible cut from amplitude alone.
        length = min(int(rate * .012), len(values) // 4)
        for index in range(length):
            gain = .5 - .5 * math.cos(math.pi * index / (length - 1))
            values[index] *= gain
            values[-1-index] *= gain
    rms = math.sqrt(sum(value * value for value in values) / len(values))
    peak = max(abs(value) for value in values)
    if rms < 0.000001 or not math.isfinite(peak):
        raise ValueError('录音为空或含无效数值')
    # A candidate balance, not a claim about perceived loudness or final mix.
    target = .035 if loop else .065
    gain = min(target / rms, .4 / peak, 4)
    return [value * gain for value in values], gain


def write_pcm(path, values, rate):
    integers = array.array('h', (round(max(-1, min(1, value)) * 32767) for value in values))
    if sys.byteorder != 'little':
        integers.byteswap()
    with wave.open(str(path), 'wb') as audio:
        audio.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
        audio.writeframes(integers.tobytes())


def main():
    output = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'build/audio-candidate'
    output = output.resolve()
    source = json.loads((SOURCE / 'Source.json').read_text())
    if source['license'] != 'CC0-1.0':
        raise ValueError('来源许可与当前候选流程不匹配')
    files = {row['name']: row for row in source['files']}
    recipes = [('purr', 'cat_purrsleepy_loop.wav', True),
               ('meow', 'cat_mewpurr2.wav', False), ('meow-soft', 'cat_softmew.wav', False),
               ('meow-short', 'cat_mewpurr.wav', False)]
    output.mkdir(parents=True, exist_ok=True)
    report = {'source_page': source['source_page'], 'author': source['author'], 'license': source['license'],
              'status': '处理文件；应用采用其中的呼噜，猫叫仍供独立试听', 'files': []}
    for name, raw, loop in recipes:
        path = SOURCE / raw
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != files[raw]['sha256']:
            raise ValueError('原始录音校验值改变，停止处理：' + raw)
        values, rate = read_pcm(path)
        prepared, gain = prepare(values, rate, loop)
        target = output / (name + '.wav')
        write_pcm(target, prepared, rate)
        decoded, decoded_rate = read_pcm(target)
        metrics = statistics(decoded, decoded_rate)
        if metrics['clipped_samples'] or metrics['peak'] > .401:
            raise ValueError('输出削波或音量超出候选约束：' + name)
        if loop and metrics['loop_boundary_step'] > .01:
            raise ValueError('呼噜循环接缝突变过大：' + name)
        if not loop and (decoded[0] != 0 or decoded[-1] != 0):
            raise ValueError('一次声首尾未淡至零：' + name)
        report['files'].append({'name': target.name, 'source': raw, 'source_sha256': digest,
                                'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
                                'gain': gain, 'loop': loop, **metrics})
    (output / 'processing.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    cards = []
    labels = {'purr.wav': '呼噜循环', 'meow.wav': '轻叫一', 'meow-soft.wav': '较轻的叫声', 'meow-short.wav': '较短的叫声'}
    for row in report['files']:
        name = html.escape(row['name'], quote=True)
        cards.append('<article><h2>'+labels[row['name']]+'</h2><audio controls preload="none" '
                     + ('loop ' if row['loop'] else '') + 'src="'+name+'"></audio><p>'
                     + f"{row['duration_seconds']:.2f}秒；峰值{row['peak']:.3f}；均方根幅度{row['rms']:.3f}。"
                     + '</p></article>')
    document = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>林间小屋：真实录音候选试听</title><style>
body{max-width:720px;margin:48px auto;padding:0 24px;background:#fbfaef;color:#405843;font:17px/1.7 system-ui}
article{background:#fffdf5;border:1px solid #d9dcc9;border-radius:16px;padding:16px 24px;margin:20px 0}
h1{font-size:28px}h2{font-size:19px}audio{width:100%}p{font-size:14px}a{color:inherit}
</style><h1>真实录音候选试听</h1><p>本页不会自动播放；每次只播放一项。呼噜会循环，可随时暂停。
应用已采用处理后的呼噜，其余猫叫仍供独立试听。请用耳机检查底噪、接缝、惊扰感，以及是否像同一只温柔的猫。</p>'''
    document += ''.join(cards)
    document += '<p>作者：Kerzoven；来源：<a href="https://opengameart.org/content/cat-purr-meow">Cat Purr &amp; Meow</a>；许可：CC0 1.0。处理参数与校验值见processing.json。</p>'
    document += '<script>document.querySelectorAll("audio").forEach(a=>{a.volume=.35;a.addEventListener("play",()=>document.querySelectorAll("audio").forEach(b=>{if(b!==a)b.pause()}))})</script></html>'
    (output / 'index.html').write_text(document)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
