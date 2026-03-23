# Diagrams on AWS Documentation

> Source: AWS internal wiki page "Diagrams on AWS Documentation" (AWS_TCX.Content_Strategy.Content_Quality.graphics.guidelines-diagrams). Last modified by jillx. This extraction preserves all textual content; images are referenced by their original filenames with descriptions derived from surrounding context.

---

## Table of Contents

- [Purpose](#purpose)
- [Diagrams on the documentation website](#diagrams-on-the-documentation-website)
- [Diagram styling cheat sheet](#diagram-styling-cheat-sheet)
- [Guideline 1. Consider the diagram size and proportion](#guideline-1-consider-the-diagram-size-and-proportion-in-relation-to-the-page-it-will-be-on)
- [Guideline 2. Use background color and padding to create balance and space](#guideline-2-use-background-color-and-padding-to-create-balance-and-space)
- [Guideline 3. Use approved visual foundations to look on-brand and professional](#guideline-3-use-approved-visual-foundations-to-look-on-brand-and-professional)
  - [3.1 Visual objects: Icons, illustrations, lines, and shapes](#31-visual-objects-icons-illustrations-lines-and-shapes)
  - [3.2 Color](#32-color)
  - [3.3 Typography: Fonts, sizes, styles, colors](#33-typography-fonts-sizes-styles-colors)
- [Guideline 4. Double-check your padding, avoid outside borders and shadows](#guideline-4-double-check-your-padding-avoid-outside-borders-and-shadows)
- [Guideline 5. Apply programmatic styles to improve the dark mode experience](#guideline-5-apply-programmatic-styles-to-improve-the-dark-mode-experience)
- [Guideline 6. Be accessible](#guideline-6-be-accessible)
- [Guideline 7. Comply with regional branding requirements](#guideline-7-comply-with-regional-branding-requirements)
  - [7.1 Usage of "AWS" in logos](#71-usage-of-aws-in-logos)
  - [7.2 Usage of "AWS" in labels and descriptive text](#72-usage-of-aws-in-labels-and-descriptive-text)
- [Need more help? Have suggestions?](#need-more-help-have-suggestions)

---

<!-- Image: banner-diagrams.png -- Page banner for "Diagrams on AWS Documentation" -->

## Purpose

This page provides visual style guidelines and other best practices (e.g., legal and accessibility compliance) for diagrams on the AWS Documentation website. A diagram creator may apply these best practices regardless of the tool or software used to create style-aligned and compliant diagrams. These guidelines assume little to no background in design.

For documentation writers and editors seeking step-by-step instructions using specific drawing tools and/or Zonbook integration, see:

- "Create, modify, and add graphics and screenshots" (internal wiki: AWSDocs/editing/graphics/)
- "Add images using zonbook" (internal wiki: AWSDocs/get-started/zonbook-reference/#HAddimages)

**New to diagrams or the docs team?** We recommend watching the Diagramming 101 training for writers on Broadcast (broadcast.amazon.com/videos/291078).

**Diagram office hours** are also available if you'd like further collaboration and guidance with your diagram. Sign up via the Documentation Diagramming Office Hours sheet.

---

## Diagrams on the documentation website

Diagrams help customers understand concepts and processes by providing a visual representation of objects and their relationships. Customers can learn about cross-service relationships, review a task that they are completing, or visualize complex data relationships. Diagrams and other types of visuals can also add visual interest, break up large blocks of text, and increase a customer's affinity towards documentation. (Source: Documentation Getting Started study, insights #3 and #12.)

Several types of diagrams can help customers understand AWS services and features. Among the categories of diagrams found in documentation, four are the most common:

### Architecture Diagram

<!-- Image: Picture1.png -- Example architecture diagram -->

**What is it**: A graphical representation of a set of concepts and objects within an ecosystem.

**Useful for:**

- Visualizing overall system or application design
- Communicating interconnected and complex relationships across services, features, and their containing contexts (such as VPC, Regions, AZs, etc.)
- Highlighting which part of the overall architecture a service or feature may serve

### Process/Flow Diagram

<!-- Image: process-flow-diagram.png -- Example process/flow diagram -->

**What is it**: A combination of illustrations, connective lines, short facts, and/or labels, that communicates a visual story or overview.

**Useful for:**

- Presenting a short and simple breakdown of workflows
- Showing users which set of tutorial steps they might be focused on with a given section/page

### Data Visualization

<!-- Image: data-viz.png -- Example data visualization -->

**What is it:** The visual presentation of data, numbers or facts in a pictorial or graphical format. Data visualizations can help customers understand difficult concepts or identify new patterns.

**Useful for:**

- Showing the relationship of one or more variables on an output (such as how time and usage impacts cost, how seasonality impacts capacity, etc.)

**Tip:** Create data visualizations using graphing tools you are comfortable with (Excel, D3, Vega-Lite, etc).

### Other Conceptual Diagram

<!-- Image: example-dg.png -- Example of a general conceptual diagram -->

**What is it:** A catch-all bucket for other types of diagrams that visually represent relationships within a system.

**Useful for:** Helping customers visualize and clarify a concept alongside its verbal explanation.

---

## Diagram Styling Cheat Sheet

Use the following cheat sheet to align your diagram's style with AWS' visual style and language. Does your diagram check off all these element guidelines?

### Diagram size and proportion

Try to keep your image mostly visible within a user's viewport and make the text big enough to be readable. Keep images from getting so big as to slow down page loading. Review the sample proportions in Guideline 1 below as a visual starting point.

Use `scalefit="1"` attribute to prevent large images from spilling over in HTML and PDF.

### Background color

Use white (#FFFFFF) in most cases. Do not leave the background transparent.

### Icons

**Icons**: Use the most up-to-date icons included in the official AWS architecture icon kit (https://aws.amazon.com/architecture/icons/). If you need an icon that is not available in the kit, consider one of the following:

1. Submit a SIM to the architecture icon team
2. Use a simple shape, like a rectangle or square with a label inside
3. Reach out to your service UX designer

**Regional compliance for icons**: Be mindful of using any icons with the terms 'AWS' embedded in the icon to comply with regional requirements. Review Usage of "AWS" in logos in Guideline 7.1 below.

**Third-party icons**: Generally, you may use 3P technology icons as long as it is accurate and educational. Do not modify another party's icon without their permission. We recommend against using general icons from open-sourced libraries, but if you have a use case that needs it, consult the trademarks team (trademarks@amazon.com) to ensure we have rights to do so.

**Callouts**: Currently being tested/iterated on updated callout styling and implementation.

### Lines and arrows

**Thickness/width:** 1pt for most cases

**Line styles:** Use **solid lines** for primary connections and containers. Secondary connections and containers can be represented as **dashed lines.**

**Arrow pointer style:** Open arrow pointers are preferred over closed ones.

<!-- Image: Screen Shot 2020-12-30 at 11.08.23 AM.png -- Arrow with open pointer (preferred) -->
<!-- Image: Screen Shot 2020-12-30 at 11.08.28 AM.png -- Arrow with closed pointer (not preferred) -->

- Arrow with open pointer (preferred)
- Arrow with closed pointer (not preferred)

### Colors

Do not modify the colors provided by official icon libraries -- use as is because they contain semantic meaning (e.g., certain colors represent a service category).

If you need to add additional colors to your diagram, make sure the color values are included within one of the following palettes:

- The AWS Brand color palette (https://design.amazon.com/styleguide/9188F3F120Af/aws/visual-guidelines/colors/)
- The Polaris (AWS UI) color palette (https://polaris.a2z.com/fundamentals/foundation/colors/)

### Typography (fonts)

- **Font:**
  - Regular text: Amazon Ember (download from the Typography website if not pre-installed)
  - Monospace text: Monaco
- **Weight**: Regular in most cases. Bold can be used for extra emphasis. Do not use Thin or Light (they fail accessibility standards below most diagram-needed font sizes).
- **Size**: 12px
- **Color**: #16191F or #000000 for most icon/illustration labels
- **Additional styling**: _Italics_ is preferred over underlines. (In a diagram with arrows/lines, underlines can add unnecessary visual noise.)

### Labels and text

**Icon labels:** Center align the label with the icon and place it under the icon.

**Descriptive text**: Do not embed explanatory text into images -- it is neither accessible nor localizable. Use only short labels for each illustrative object or icon. If you'd like to highlight specific parts of the diagram with explanatory text, use callouts. This is better for accessibility, localization, and regional compliance.

**Regional compliance for labels/text**: Ensure that usage of the term 'AWS' complies with regional requirements. Review Usage of "AWS" in text in Guideline 7.2 below.

### Outside framing

**Padding**: Apply 8px equally to the top, bottom, left, and right of your image.

**Border**: Do not apply a visible outside border to the diagram, and we recommend staying away from border shadows and fades.

### Dark mode optimization

Optimize your image for dark mode by testing out different style attributes. (See Guideline 5 for details.)

### Accessibility

Keep most of the text in your documentation, not the graphic. Use alt text when adding your graphic to a guide. (See Guideline 6 for details.)

### Regional compliance

Diagrams that display on the China website have to meet the China branding requirements. If your image contains the AWS logo or "AWS" as a term, you have the following options:

1. Profile out the image that is not compliant, and make appropriate modifications to your text if it refers to an image (low effort, sacrifice customer experience).
   - For example, you can add the Region attribute such as `<mediaobject region="SEA;IAD;LCK;DCA">`, which means the image will appear on all doc websites except the China website. For more information, see Region profiling in service doc content.
2. Edit your version of the image to work globally if possible (medium effort, baseline customer experience).
3. Create two different images that comply with each area's legal standards, and profile images accordingly (high effort, optimized customer experience).

---

## Guideline 1. Consider the diagram size and proportion in relation to the page it will be on

Your decisions about image size and aspect ratio play an important part with overall layout balance and image readability. In the examples below, screens A-G display examples of recommended image size proportions -- the images in each example are fully visible to the user in common browser viewports, and allow the user to stay within the context of what they are learning about by keeping some of the explanatory text in view. Screens H and I exemplify proportions that should be used sparingly, with careful consideration.

<!-- Image: guides-size.png -- Grid showing screens A through I with different diagram size proportions. A-G are recommended; H and I should be used sparingly. Shows how diagrams of various aspect ratios appear within a browser viewport alongside explanatory text. -->

---

## Guideline 2. Use background color and padding to create balance and space

Background color and padding settings are very important for images on the documentation website. Please review this section and make sure that your images:

1. **Have a background color set** -- do **not** save your image with a transparent background
2. **Are saved with an equal amount of padding** to the top, right, bottom, and left of your image (8px in most cases)

These settings are important to reduce future reliance on programmatic attributes to optimize images. (At dark mode launch, programmatic filters for background, padding, and brightness filter were used to optimize images for dark mode. Moving beyond that, background and padding should be saved within the image itself and reduce the number of dark mode filters to solely brightness filter.)

### Examples of background and padding issues

#### Good example -- light mode

<!-- Image: bp-light.png -- Architecture diagram in light mode with good internal spacing and even external padding -->

**Spacing within the image:** When creating your image, consider your usage of background and white space as part of your overall image. Make sure you leave sufficient "breathing room" space between the objects in your images so that they feel pleasing to look at instead of crammed and uncomfortable.

**Spacing around the image**: Make sure you leave an even amount of white space to the top, bottom, left, and right of the image. On light mode, this may not be as important because you can rely on the background color of the website to hide any uneven edges.

However, on dark mode, uneven padding and overlooked backgrounds become very clear.

#### Bad example -- transparent background in dark mode

<!-- Image: bp-d1.png -- Architecture diagram shown in dark mode with NO background color set (transparent). Visual objects and text are difficult to see against the dark page background. -->

**Important**: Make sure you set your background to a color (usually white) before you save. Some imagery software defaults to a transparent background, which can lead to difficult-to-see visual objects and text like shown here. If customers cannot distinguish the shapes or read your image, the image is not acceptable.

#### Bad example -- no outside padding in dark mode

<!-- Image: bp-d2.png -- Architecture diagram in dark mode with a white background but NO outside padding. The image feels tight, and the borderlines of the Region container are very hard to distinguish, compromising the architectural understandability. -->

**Important**: The padding around the main area of your image is also important. In this example, we have a white background, but there is no outside padding. This makes the image feel tight, and the borderlines of the Region container are very hard to distinguish, thus compromising the architectural understandability of the image.

#### Bad example -- unequal padding (left side only) in dark mode

<!-- Image: bp-d3.png -- Architecture diagram in dark mode with padding on the left side only, but no padding on top, right, or bottom. The image looks uneven and lopsided. -->

**Important**: Equal padding around all sides (top, bottom, left, right) of your image is important. In this example, there is padding included on the left, but not to the top, right, or bottom -- which results in an image that looks uneven and lopsided in dark mode.

#### Bad example -- unequal padding on all sides in dark mode

<!-- Image: bp-d4.png -- Architecture diagram in dark mode with padding included unequally across all sides. The image looks uneven and lopsided. -->

This is another example of the point mentioned above. In this example, padding is included unequally across all sides, therefore resulting in an image that looks uneven and lopsided in dark mode.

#### Best practice example -- equal padding on all four sides

<!-- Image: bp-d5.png -- Architecture diagram in dark mode with equal padding on all four sides (8px). The image looks balanced and intentional in both light and dark modes. -->

**Best practice example:** Equal padding included around all four sides of the main image (8px in most cases) results in an image that looks balanced and intentional in both light and dark modes.

---

## Guideline 3. Use approved visual foundations to look on-brand and professional

There are several elements that can help make your image look visually aligned to the AWS brand, and to one another as users browse from page to page across user guides:

1. Use the AWS-aligned visual objects
2. Use brand-approved colors
3. Use consistent and approved type ramp

### 3.1 Visual objects: Icons, illustrations, lines, and shapes

Visual objects are used to represent an entity or a concept -- things like an AWS service, AWS in general, user groups, the sun, or the concept of 'forward momentum'. The visual object can range from actually looking like the object (e.g., an image of the sun can have some resemblance to the actual sun) or be very abstracted (e.g., a compute instance may not have a commonly-known or actual physical representation, so we make one up). At AWS, we have mixed ranges of defined visual language and styling applied for categories of concepts. Review the table below to understand the stylistic differences and the best practices for including them in your diagram.

**Note**: Company/organization logos are also visual objects used on the Documentation website. These should be used sparingly, with approval (by the organization and our internal team) and following the organization's logo usage guidelines.

#### Category icons, service icons, resource icons

<!-- Image: category-service-resource_icons.png -- Shows three rows of AWS icons: (1) Category icons (top row, colored squares with white silhouette icons representing service categories like Compute, Storage, Database), (2) Service icons (middle row, individual service icons like EC2, S3, RDS with their standard colored backgrounds), (3) Resource icons (bottom row, smaller detailed resource-level icons representing sub-components of services). Dimensions: 280x400px -->

- Make sure you are using the most up-to-date versions of the icons (https://aws.amazon.com/architecture/icons/). The AWS Marketing design team, who manages these icons, updates the icon set on a quarterly basis for Microsoft PowerPoint. While you may find icons in other diagramming tools, they may be outdated.
- Use the light-background version.
- Service icons come in two forms: the Standard service icon and the Alternate service icon. Use the Standard service icons for your diagrams (the Alternate ones will eventually become deprecated).

#### General icons and illustrations

<!-- Image: general-icons.png -- Shows examples of general-purpose AWS icons and illustrations (e.g., users, cloud, internet, generic server, corporate data center, mobile client). These are non-service-specific icons from the AWS icon kit used to represent general concepts. Dimensions: 280x400px -->

Use AWS-approved/created general icons and illustrations to keep aligned with AWS visual styling. Using non-approved third-party illustrations may lead to unwanted legal consequences. You can retrieve approved illustrations by:

- Using the "general icons" from the AWS Icon set (https://aws.amazon.com/architecture/icons/)
- Using the AWS Illustration Library from the AWS brand portal (https://brand.amazon.com/aws/visual-guidelines/illustrations/)
- Submitting a request for a general icon to the AWS Marketing team
- Asking your service designer for assets
- If an illustration you need is unavailable, consider creating your own simple illustration with basic shapes instead

#### General icons from third party or open-source providers

Generally, we do not recommend using general icons from third party/open-sourced providers. If you need a generic icon, submit a request to the AWS Marketing team to include it as part of their architecture diagram set. If your use case still requires third party sources, consider the risks of nuanced and downstream trademark/copyright infringement that may occur. We recommend consulting with the AWS Trademark team (trademarks@amazon.com) before using open-sourced icons.

#### Third-party technology icons/logos

<!-- Image: 3p-tech.png -- Shows examples of third-party technology icons/logos that might appear in AWS architecture diagrams (e.g., Kubernetes, Docker, Linux, etc.). Dimensions: 280x348px -->

As a general rule, you may use a third party technology icon as part of an educational/referential diagram if that organization has publicly published the icon along with expressed written permissions to use it.

**Do:**

- Use icons in a way that is truthful and accurate
- Check the 3P's website for published logos/icons and licensing rules
- Review the Customer Reference Finder database for customers who have permitted us to use their logos
- If you are working directly with a company and you ask for permissions via email, save the email

**Don't:**

- Don't modify styling of 3P icons (e.g., adding borders, adding or changing colors, cropping, scaling disproportionately, adding text, etc.)
- Don't use 3P icons in a way that may suggest an endorsement, affiliation, or sponsorship/co-branding (e.g., combining logos into one logo, implying a relationship between two products)

#### Basic shapes

<!-- Image: basic-shapes.png -- Shows examples of basic shapes used in AWS diagrams: squares, rectangles, circles, and rounded rectangles with various fill colors from the AWS palette and 1px borders. Fill colors use "AWS Light" tints; border colors use the regular tints. Dimensions: 280x400px -->

- Keep your shapes basic when possible: squares, rectangles, circles, and triangles
- If you're using a square or rectangle, include a 1px border radius (most diagramming/graphics tools should have this setting)
- Shapes that have associated connotations (hearts, crosses, lightning bolts, etc) should be avoided in most cases -- use your best judgement
- Select fill colors from the approved color palettes
- If you are adding a border, keep it at 1px and keep the colors aligned. For example, the "AWS Light" tints of the brand color palette can be used for fills while the regular tints of the colors are used for borderlines.

#### Lines and arrows

<!-- Image: lines-arrows.png -- Shows examples of line and arrow styles: solid lines, dashed lines, open arrow pointers, and closed arrow pointers. Line widths are 1-2px. Colors are from the approved AWS palettes. Dimensions: 280x400px -->

- Keep the width at 1-2px on most diagramming software
- Select colors from the approved color palettes, and make sure the lines are visible
- For arrows, use the line-based, unfilled arrow pointers

#### Callouts (TBD)

We are currently testing and iterating on updated callout styling and implementation. Contact the graphics team if you have a use case you want to work through.

### 3.2 Color

AWS has two approved color palettes:

1. **AWS Brand color palette** -- mostly used for illustrations, icons, and banners
2. **AWS Design System color palette (Polaris)** -- mostly used for UI elements (e.g., components and buttons)

If you are using visual objects (icons and illustrations) from the AWS Marketing library, you will already be using approved colors. If you need to create your own shapes for diagrams and data visualizations, make sure you use colors from one of these two palettes. Most diagramming software will allow you to plug in hex color codes and/or RGB values and/or import color palettes.

To test AWS colors for contrast accessibility, enter AWS hex color codes into the WebAIM color contrast checker: https://webaim.org/resources/contrastchecker/

#### AWS Brand color palette

<!-- Image: Screen Shot 2021-12-01 at 1.18.59 PM.png -- Preview of the AWS Brand color palette showing multiple color families (oranges, blues, greens, purples, pinks, teals, etc.) in varying tints from dark to light. Each color family includes standard and "AWS Light" variants. Full hex codes and RGB values available on the AWS Brand website. Dimensions: 500x501px -->

See the full set, along with hex codes and RGB values, on the AWS Brand website: https://design.amazon.com/styleguide/9188F3F120Af/aws/visual-guidelines/colors/

#### AWS Design System (Polaris) color palette

<!-- Image: Screen Shot 2020-06-08 at 8.31.54 AM.png -- Preview of the AWS Design System (Polaris) color palette showing color swatches organized in rows by color family, with numbered intensity levels. Includes greys, blues, greens, reds, oranges, and other UI-focused colors. Dimensions: 733x274px -->

See the full set, along with the hex codes, on the AWS Design System website: https://polaris.a2z.com/fundamentals/foundation/colors/

### 3.3 Typography: Fonts, sizes, styles, colors

Use typography rules consistently within your image and make sure they are large enough to be readable. Aim to keep your text limited to labels and very short descriptions if you absolutely need them. Otherwise, rely on your actual content to explain the image, so that the text can translate to non-English languages and be picked up by assistive technologies.

#### Font, weight, size, emphasis

**Regular text:**

- **Font:** Amazon Ember (download from the Typography website: http://typography.aka.amazon.com/fonts/0 if not pre-installed)
- **Weight/style:** Regular, **Bold**, or _Italic_. Stay away from underlines -- the lines can add unnecessary visual noise and introduce room for confusion with connective lines and arrows.
- **Size:** 12px (larger is OK for certain circumstances, but no smaller)

**Monospace text:**

- **Font:** Use one of the following: **Monaco, Menlo, Consolas, Courier Prime, Courier, Courier New**
- **Weight/style:** Regular or **Bold**
- **Size:** 12px (larger is OK for certain circumstances, but no smaller)

#### Font color

- Most text should be **#16191F** or **#000000** (black).
- If you need additional font colors, pick within the approved color set mentioned in the previous section.
- To make text, graphics, and UI components accessible and clearly readable, use the WebAIM contrast checker (https://webaim.org/resources/contrastchecker/) with AWS Brand colors.

---

## Guideline 4. Double-check your padding, avoid outside borders and shadows

This guideline is a reiteration of Guideline 2. When you finish creating your image and get ready to save, triple-check that you have even padding to the top, left, right, and bottom of the focus of your image. Additionally, make sure that your image software didn't sneak in an unwanted border or outline shadow while saving your image (this sometimes happens).

### Non-recommended: Border

<!-- Image: border.png -- Architecture diagram with a visible border surrounding the Region containers. This outer border is not recommended. Dimensions: 592x355px -->

Image with non-recommended border surrounding the Region containers.

### Non-recommended: Shadow

<!-- Image: shadow.png -- Architecture diagram with a visible shadow effect surrounding the Region containers. This outer shadow is not recommended. Dimensions: 592x352px -->

Image with non-recommended shadow surrounding the Region containers.

---

## Guideline 5. Apply programmatic styles to improve the dark mode experience

Programmatic styles automatically apply style attributes to your image so they can be optimized when a customer views documentation on dark mode. By default, images have a default style attribute applied to add a white background and 15px padding across the top, bottom, left, and right, as a safety catch-all for images that needed them during the migration to dark mode. To learn more and see step-by-step instructions on how to test these filters, see "Programmatic visual treatments" (internal wiki: AWSDocs/editing/graphics/darkmode/).

If you're creating a new image and you followed the guidelines on this page, you will most likely use one of the following two style attributes:

- Use **`bg-padding-filter`** if your image has a white background color
- Use **`notreatment`** if your image has a non-white background color

---

## Guideline 6. Be accessible

Make sure that your graphics or the concepts that they describe are accessible to customers who use screen readers, or who may have color perception or other vision issues. For more information, see the AWS Style Guide topic on Accessibility (https://alpha-docs-aws.amazon.com/awsstyleguide/latest/styleguide/accessibility.html).

- Keep text in a graphic limited to labels and callouts.
- Move the workflow description or a short summary of the important concepts to the main content, so that it can be read by a screen reader.
- Avoid mentioning colors.
- Provide enough contrast in the image so that it can be perceived by people with moderately low vision.
- **Add alt text:**
  - Write a concise description of the image. Try to keep this description under 100 characters if possible, and avoid repeating text that is already used elsewhere in the content.
    > **Note:** For some complex images such as charts or workflow diagrams, a 100-character description might not be adequate to fully convey the content of the image. In this case, ensure that you are providing a more detailed description in the main content of the page, above or below the image. The alt text itself should then concisely describe the _general_ content of the image.
  - Don't mention the type of image it is, unless the type of image is the point of the content. That's because screen readers already say "Image of" at the beginning of each alt text vocalization.
    - Instead of writing "picture of..." or "graphic of..." or "screenshot of...", describe only the main point of the image in relation to the content.
    - For something like a workflow diagram, describe the graphic's important elements "as a workflow" or "depicted in a workflow."
  - Include terminal punctuation.
  - For hyperlinked graphics, include the destination.

---

## Guideline 7. Comply with regional branding requirements

Any reference to the term "AWS" in any diagram to the audience in Mainland China (docs.amazonaws.cn) needs to be evaluated and modified to follow trademark guidelines. In general, there are two elements that the China branding requirements impact:

1. Usage of "AWS" in logos
2. Usage of "AWS" in text

### 7.1 Usage of "AWS" in logos

Do not use any icons that contain "AWS" if you are planning to publish the diagram on the China site. Commonly, architecture diagrams might include an icon and label to represent AWS and its boundaries within an architecture. You will need to change the icon and the label to comply with the China rebranding. Review the examples below for common examples and resolution options.

#### Not compliant for the China site

<!-- Image: Artboard-1.png -- Three different architecture diagrams showing three different styles of AWS cloud icon styling (highlighted with red circles). Each uses the AWS logo/icon in a way that is not compliant with China branding requirements. -->

In this image, you see three different styles of AWS cloud icon styling (highlighted with red circles) on three different generations of architecture diagrams.

#### Compliant for the China site

<!-- Image: Artboard-2.png -- The same three architecture diagrams modified to be compliant. Option 1: The AWS Logo icon is completely removed, and its label has changed from "AWS Cloud" to "Amazon Web Services Cloud." Options 2 and 3: A generic cloud logo is used, fitting with the architecture diagram's overall style. -->

In this image, you see different approaches to meet the China rebranding requirement:

- **Option 1:** The AWS Logo icon is completely removed, and its label has changed from "AWS Cloud" to "Amazon Web Services Cloud."
- **Options 2 and 3:** A generic cloud logo is used, fitting with the architecture diagram's overall style.

If you are using the latest architecture diagram icon set, the generic cloud icon is available in the Architecture Diagram kit (https://aws.amazon.com/architecture/icons/).

### 7.2 Usage of "AWS" in labels and descriptive text

Diagrams might contain labels and descriptive text for AWS services, features, and other elements. You may need to change the labels or profile the image out to comply with the China rebrand -- consult the rebranding summary to check if any diagram text or labels need to be modified, and review the compliant examples below.

#### Labels -- Not compliant

<!-- Image: service-labels.png -- Architecture diagram where the container and services include the label "AWS" (e.g., "AWS Lambda", "AWS Cloud"). This is not compliant for the China site. -->

In this image, the container and services include the label "AWS".

#### Labels -- Compliant options

**Option 1:** Profile the image out for the China site version of the website, and ensure surrounding text does not include references to an image.

<!-- Image: global_china_2.png -- Shows how to profile out an image so it does not appear on the China website version. The image is shown for the global site only. -->

**Option 2:** Create compliant Region-specific versions of the diagram.

<!-- Image: global-china_1.png -- Shows two versions of the same diagram side by side: one for the global site (with "AWS" labels) and one for the China site (with "AWS" removed or replaced with full legal entity names). -->

**Option 3:** Create a Region-neutral version of the diagram that you can use across all locales by omitting the legal entity of the service/element. To do this, you must ensure that your image is preceded by written text that contains the full service name present in the diagram so you can take advantage of the "subsequent use rule" within the diagram.

<!-- Image: service-labels_option-3.png -- Shows a Region-neutral diagram where service labels omit "AWS" (e.g., just "Lambda" instead of "AWS Lambda"), relying on the preceding text to establish the full service name. -->

**Note:** This option is not valid if your diagram contains a label within the "Important Exceptions" list. In that case, use Option 1 or Option 2.

#### Descriptive text -- Not compliant

<!-- Image: embedded-text.png -- Architecture diagram where the term "AWS" is embedded as description text (not just labels) for a corresponding illustration. -->

In this image, the term "AWS" is embedded as description text for a corresponding illustration.

#### Descriptive text -- Compliant options

**Recommended:** Don't embed explanatory text into images. Use only short labels for each illustrative object or icon. Instead, use callouts to refer to certain aspects of the image you want to describe more with text. This is better for accessibility, localization, and the China rebrand.

**Alternate option:** Modify the image's embedded text to remove references to "AWS."

---

## Need more help? Have suggestions?

Leave a comment and/or email aws-doc-graphics@amazon.com and let's discuss!

---

## Image Reference Index

The following images were referenced in the original document. They are not embedded in this markdown file but are listed here for completeness. Original filenames correspond to the `XWiki_files/` directory of the saved HTML page.

| Filename                                    | Context / Description                                                                                                        |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `banner-diagrams.png`                       | Page banner image                                                                                                            |
| `Picture1.png`                              | Architecture diagram example (diagram types table)                                                                           |
| `process-flow-diagram.png`                  | Process/flow diagram example (diagram types table)                                                                           |
| `data-viz.png`                              | Data visualization example (diagram types table)                                                                             |
| `example-dg.png`                            | Other conceptual diagram example (diagram types table)                                                                       |
| `guides-size.png`                           | Guideline 1 -- Grid of screens A-I showing recommended vs. not-recommended diagram size proportions within browser viewports |
| `bp-light.png`                              | Guideline 2 -- Good example: diagram in light mode with proper spacing and padding                                           |
| `bp-d1.png`                                 | Guideline 2 -- Bad example: transparent background in dark mode; objects/text hard to see                                    |
| `bp-d2.png`                                 | Guideline 2 -- Bad example: white background but no outside padding in dark mode                                             |
| `bp-d3.png`                                 | Guideline 2 -- Bad example: unequal padding (left only) in dark mode                                                         |
| `bp-d4.png`                                 | Guideline 2 -- Bad example: unequal padding on all sides in dark mode                                                        |
| `bp-d5.png`                                 | Guideline 2 -- Best practice: equal 8px padding on all four sides in dark mode                                               |
| `category-service-resource_icons.png`       | Guideline 3.1 -- Shows category icons, service icons, and resource icons from the AWS architecture icon kit                  |
| `general-icons.png`                         | Guideline 3.1 -- Shows general-purpose AWS icons and illustrations (users, cloud, internet, etc.)                            |
| `3p-tech.png`                               | Guideline 3.1 -- Shows third-party technology icons/logos used in diagrams                                                   |
| `basic-shapes.png`                          | Guideline 3.1 -- Shows basic shapes (squares, rectangles, circles) with AWS palette fills and borders                        |
| `lines-arrows.png`                          | Guideline 3.1 -- Shows line and arrow style examples (solid, dashed, open/closed pointers)                                   |
| `Screen Shot 2020-12-30 at 11.08.23 AM.png` | Cheat sheet -- Arrow with open pointer (preferred style)                                                                     |
| `Screen Shot 2020-12-30 at 11.08.28 AM.png` | Cheat sheet -- Arrow with closed pointer (not preferred)                                                                     |
| `Screen Shot 2021-12-01 at 1.18.59 PM.png`  | Guideline 3.2 -- AWS Brand color palette preview                                                                             |
| `Screen Shot 2020-06-08 at 8.31.54 AM.png`  | Guideline 3.2 -- AWS Design System (Polaris) color palette preview                                                           |
| `border.png`                                | Guideline 4 -- Diagram with non-recommended visible border around Region containers                                          |
| `shadow.png`                                | Guideline 4 -- Diagram with non-recommended shadow around Region containers                                                  |
| `Artboard-1.png`                            | Guideline 7.1 -- Three AWS cloud icon styles that are NOT compliant for China site (highlighted with red circles)            |
| `Artboard-2.png`                            | Guideline 7.1 -- Compliant alternatives: removed AWS logo, changed label, or used generic cloud icon                         |
| `service-labels.png`                        | Guideline 7.2 -- Labels not compliant: services labeled with "AWS" prefix                                                    |
| `global_china_2.png`                        | Guideline 7.2 -- Labels Option 1: profile out the image for the China site                                                   |
| `global-china_1.png`                        | Guideline 7.2 -- Labels Option 2: Region-specific diagram versions (global vs. China)                                        |
| `service-labels_option-3.png`               | Guideline 7.2 -- Labels Option 3: Region-neutral diagram omitting "AWS" from labels                                          |
| `embedded-text.png`                         | Guideline 7.2 -- Descriptive text not compliant: "AWS" embedded as description text                                          |
| `logo.png`                                  | Site logo (navigation chrome, not content)                                                                                   |
