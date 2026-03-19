---
title: "Link Abbreviations in Markdown"
permalink: /docs/link-abbr-md/
last_modified_at: 2026-03-17
toc: true
toc_sticky: true
link_abbrs:
  - link_abbr: foo https://i.postimg.cc/Vv8jFw8D/
gallery:
  - url: foo:unsplash-gallery-image-1.jpg
    image_path: foo:unsplash-gallery-image-1.jpg
    title: Check this [[foo:unsplash-gallery-image-1.jpg][image]]
  - image_path: foo:unsplash-gallery-image-1.jpg
  - foo:unsplash-gallery-image-1.jpg
---

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
gallery:
  - url: foo:unsplash-gallery-image-1.jpg
    image_path: foo:unsplash-gallery-image-1.jpg
    title: Check this [image](foo:unsplash-gallery-image-1.jpg)
  - image_path: foo:unsplash-gallery-image-1.jpg
  - foo:unsplash-gallery-image-1.jpg
---

{% include gallery columns=6 caption="A gallery using link abbreviations " %}
```
{% endraw %}

All the link forms shown above can be expanded correctly to the same image path:

{% include gallery columns=6 caption="A gallery using link abbreviations " %}
