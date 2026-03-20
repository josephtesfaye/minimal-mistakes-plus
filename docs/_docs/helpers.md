---
title: "Helpers in Markdown"
permalink: /docs/helpers-md/
last_modified_at: 2026-03-17
toc: true
toc_sticky: true
symlinks:
  - /assets/archive/image/foo ~/Downloads/temp/archive/image/foo
link_abbrs:
  - link_abbr: foo https://i.postimg.cc/Vv8jFw8D/
  - link_abbr: foo2 /assets/archive/image/foo/
gallery2:
  - url: foo:unsplash-gallery-image-1.jpg
    image_path: foo:unsplash-gallery-image-1.jpg
    title: Here is a [link]({{ site.baseurl }}/docs/dark-mode/) in title.
  - image_path: foo:unsplash-gallery-image-1.jpg
  - foo:unsplash-gallery-image-1.jpg
gallery3:
  - url: foo2:unsplash-gallery-image-1.jpg
    image_path: foo2:unsplash-gallery-image-1.jpg
    title: Here is a [link]({{ site.baseurl }}/docs/dark-mode/) in title.
  - image_path: foo2:unsplash-gallery-image-1.jpg
  - foo2:unsplash-gallery-image-1.jpg
---

# Link Abbreviations

Here are demos of link abbreviations used in Markdown. The creation of link
abbreviations is the same as in [Org Mode]({{ site.baseurl }}/docs/link-abbr/).

To create a link abbreviation, in the front matter add the abbreviation and its
full form in a `link_abbr` in the `link_abbrs` array, like this:

``` markdown
link_abbrs:
  - link_abbr: foo https://i.postimg.cc/Vv8jFw8D/
```

Then you can use the abbreviation in links throughout the document. It will be
expanded to the full form in the built site.

Below are the supported use cases of link abbreviations.

## Standard Markdown Links

Here is an image:

``` markdown
![](foo:unsplash-gallery-image-1.jpg)
```

![](foo:unsplash-gallery-image-1.jpg)

## Figure

Links written in Liquid syntax are also supported. For example, here is a
figure:

{% raw %}
``` markdown
{% include figure image_path="foo:unsplash-gallery-image-1.jpg" popup=true
alt="" caption="A figure" %}
```
{% endraw %}

{% include figure image_path="foo:unsplash-gallery-image-1.jpg" popup=true
alt="" caption="A figure" %}

## Gallery

You can create a gallery as usual in [Minimal
Mistakes](https://mmistakes.github.io/minimal-mistakes/docs/helpers/#gallery).
The extra benefit is that now you can use link abbreviations in it, like this:

{% raw %}
``` markdown
---
link_abbrs:
  - link_abbr: foo https://i.postimg.cc/Vv8jFw8D/
gallery2:
  - url: foo:unsplash-gallery-image-1.jpg
    image_path: foo:unsplash-gallery-image-1.jpg
    title: Here is a [link]({{ site.baseurl }}/docs/dark-mode/) in title.
  - image_path: foo:unsplash-gallery-image-1.jpg
  - foo:unsplash-gallery-image-1.jpg
---

{% include gallery id="gallery2" columns=6 caption="A gallery using link abbreviations " %}
```
{% endraw %}

All the link forms shown above can be expanded correctly to the same image path:

{% include gallery id="gallery2" columns=6 caption="A gallery using link abbreviations " %}

# Loading Local Files

A gallery loading local files:

{% raw %}
``` markdown
---
symlinks:
  - /assets/archive/image/foo ~/Downloads/temp/archive/image/foo
link_abbrs:
  - link_abbr: foo2 /assets/archive/image/foo/
gallery3:
  - url: foo2:unsplash-gallery-image-1.jpg
    image_path: foo2:unsplash-gallery-image-1.jpg
    title: Here is a [link]({{ site.baseurl }}/docs/dark-mode/) in title.
  - image_path: foo2:unsplash-gallery-image-1.jpg
  - foo2:unsplash-gallery-image-1.jpg
---

{% include gallery id="gallery3" columns=6 caption="A gallery using link abbreviations " %}
```
{% endraw %}

{% include gallery id="gallery3" columns=6 caption="A gallery using link abbreviations " %}

# Furigana

You can write furigana for Japanese Kanji words like the following:

``` text
本｜日（ほん｜じつ）はお時｜間（じ｜かん）をいただき、ありがとうございます。私は
マカオにあるマカオ理｜工｜大｜学（り｜こう｜だい｜がく）を4年｜制（ねん｜せい）
の学｜士（がく｜し）課｜程（か｜てい）で卒業（そつ｜ぎょう）しました。
```

本｜日（ほん｜じつ）はお時｜間（じ｜かん）をいただき、ありがとうございます。私は
マカオにあるマカオ理｜工｜大｜学（り｜こう｜だい｜がく）を4年｜制（ねん｜せい）
の学｜士（がく｜し）課｜程（か｜てい）で卒業（そつ｜ぎょう）しました。

You can also write furigana for ~Katakana（English）~ pairs, that is, if matched,
put the English above the Katakana word just like furigana. For example:

``` text
クラウド（cloud）ネイティブ（native）なマルチテナント（multi-tenant）型バックエ
ンド（backend）プラットフォーム（platform）の設計
```

クラウド（cloud）ネイティブ（native）なマルチテナント（multi-tenant）型バックエ
ンド（backend）プラットフォーム（platform）の設計
