// The Hugh Tran site's icon set: engraved line icons, drawn on a 24-unit grid in two weights,
// like a woodcut line: a heavy `stroke` and a fine `hair`, plus solid `fill` for small masses.
// Parts marked `detail` are only drawn at text and display sizes; the caption cut (small sizes)
// leaves them out so each icon keeps one clear idea. Weights per size come from the Brand Codex
// (brand/seed.json, `icon`), never from here. See src/components/Icon.astro.
//
// Every icon stands for one idea, and the same idea gets the same icon everywhere:
// a menu section, a Lab kind or a button.

export type Part = { d: string; w: 'stroke' | 'hair' | 'fill'; detail?: true };
export type IconDef = { title: string; why: string; parts: Part[] };

const s = (d: string, detail?: true): Part => ({ d, w: 'stroke', ...(detail && { detail }) });
const h = (d: string, detail?: true): Part => ({ d, w: 'hair', ...(detail && { detail }) });
const f = (d: string, detail?: true): Part => ({ d, w: 'fill', ...(detail && { detail }) });

export const ICONS = {
  // ---------- Main menu ----------
  readings: {
    title: 'Readings',
    why: 'A card with a star: cartomancy and astrology, the two kinds of reading.',
    parts: [
      s('M6.5 2.5h11a1 1 0 0 1 1 1v17a1 1 0 0 1-1 1h-11a1 1 0 0 1-1-1v-17a1 1 0 0 1 1-1z'),
      f('M12 7.4l1.3 3.3 3.3 1.3-3.3 1.3L12 16.6l-1.3-3.3L7.4 12l3.3-1.3z'),
      f('M8.9 5.1a.7.7 0 1 1-1.4 0a.7.7 0 1 1 1.4 0zM16.5 18.9a.7.7 0 1 1-1.4 0a.7.7 0 1 1 1.4 0z', true),
    ],
  },
  journal: {
    title: 'Journal',
    why: 'An open book: essays to read, written leaf by leaf.',
    parts: [
      s('M12 6.4C10 4.9 6.5 4.4 2.75 4.9v13.6c3.75-.5 7.25 0 9.25 1.5c2-1.5 5.5-2 9.25-1.5V4.9C17.5 4.4 14 4.9 12 6.4z'),
      h('M12 6.4V20'),
      h('M5.4 8.6c1.8-.1 3.3.2 4.4.8M5.4 11.6c1.8-.1 3.3.2 4.4.8M5.4 14.6c1.8-.1 3.3.2 4.4.8M14.2 9.4c1.1-.6 2.6-.9 4.4-.8M14.2 12.4c1.1-.6 2.6-.9 4.4-.8M14.2 15.4c1.1-.6 2.6-.9 4.4-.8', true),
    ],
  },
  press: {
    title: 'Press',
    why: 'A hand press, lever and all: the Press prints books, zines, prints and type.',
    parts: [
      s('M3.75 4.75h14.5M6 4.75v16.75M16 4.75v16.75M3 21.5h15.75'),
      s('M11 4.75v6'),
      h('M11 7.75h10'),
      f('M22.3 7.75a1.15 1.15 0 1 1-2.3 0a1.15 1.15 0 1 1 2.3 0z'),
      s('M8 10.75h6v2.25H8z'),
      h('M7.75 18h6.5'),
      h('M8.75 16.25h4.5', true),
    ],
  },
  classes: {
    title: 'Classes',
    why: 'An oil lamp, the lamp of learning: study by its light.',
    parts: [
      s('M3 13h13.5c0 3.4-3 5.8-6.75 5.8S3 16.4 3 13z'),
      s('M16.5 13l3.75-2.25'),
      s('M20.25 9.4c-1.7-.9-1.8-3.3 0-6.1c1.8 2.8 1.7 5.2 0 6.1z'),
      h('M3.2 14.4c-2.1.1-2.2-3.3-.1-3.4'),
      h('M7.5 13c0-1 1-1.7 2.25-1.7S12 12 12 13', true),
      h('M7.9 18.7l-.6 2.8h4.9l-.6-2.8', true),
    ],
  },
  lab: {
    title: 'Lab',
    why: 'A flask on a stand over a flame: the Laboratorium, where things are made and tested.',
    parts: [
      s('M9.75 2.75h4.5M10.75 2.75v4.42A4.75 4.75 0 1 0 13.25 7.17V2.75'),
      h('M7.6 13h8.8'),
      s('M6.5 17.75h11', true),
      h('M7.75 17.75l-1.6 3.75M16.25 17.75l1.6 3.75', true),
      f('M12 22.25c-1.4 0-2.1-1-1.75-2.2c.3-.8 1-1.2 1.2-2.15c.85.65 2.15 1.85 2.15 2.95c0 .8-.65 1.4-1.6 1.4z'),
      f('M11.4 14.9a.6.6 0 1 1-1.2 0a.6.6 0 1 1 1.2 0zM13.7 14.5a.45.45 0 1 1-.9 0a.45.45 0 1 1 .9 0z', true),
    ],
  },
  about: {
    title: 'About',
    why: 'A cameo portrait: the person behind the work.',
    parts: [
      s('M19.5 12c0 5.25-3.36 9.5-7.5 9.5S4.5 17.25 4.5 12S7.86 2.5 12 2.5s7.5 4.25 7.5 9.5z'),
      h('M14.7 9.9a2.7 2.7 0 1 1-5.4 0a2.7 2.7 0 1 1 5.4 0z'),
      h('M7.4 18.4c.8-2.7 2.5-4.1 4.6-4.1s3.8 1.4 4.6 4.1'),
    ],
  },
  studio: {
    title: 'HTD Studio',
    why: 'A curve with its handles, the type and design tool: Hugh’s design studio.',
    parts: [
      s('M3 19.5C5.5 12.5 8.6 10 12 10s6.5 2.5 9 9.5'),
      h('M5 10h14'),
      s('M10.6 8.6h2.8v2.8h-2.8z'),
      f('M3.6 10a1.4 1.4 0 1 1 2.8 0a1.4 1.4 0 1 1-2.8 0zM17.6 10a1.4 1.4 0 1 1 2.8 0a1.4 1.4 0 1 1-2.8 0z'),
      f('M1.75 18.25h2.5v2.5h-2.5zM19.75 18.25h2.5v2.5h-2.5z'),
    ],
  },

  search: {
    title: 'Search',
    why: 'A reading glass: look for something.',
    parts: [
      s('M16.6 10a6.6 6.6 0 1 1-13.2 0a6.6 6.6 0 1 1 13.2 0z'),
      h('M6.6 7.4a4.6 4.6 0 0 1 2.6-1.6', true),
      f('M14.05 15.45l1.4-1.4l6 6a1 1 0 0 1-1.4 1.4z'),
    ],
  },

  // ---------- Lab: kinds of work ----------
  all: {
    title: 'All',
    why: 'The ouroboros, the serpent swallowing its tail: the whole of the work, every kind in one ring.',
    parts: [
      s('M13.94 5.26A7.5 7.5 0 1 1 5.86 8.2'),
      h('M8.83 5.7A7.5 7.5 0 0 1 13.94 5.26'),
      f('M4.24 9A3.25 2.1 -38 1 1 9.36 5A3.25 2.1 -38 1 1 4.24 9zM7.5 5.25a.65.65 0 1 0 0 1.3a.65.65 0 1 0 0-1.3z'),
    ],
  },
  project: {
    title: 'Project',
    why: 'Dividers: a measured, planned piece of work that runs over time.',
    parts: [
      s('M12 1v1.4'),
      f('M14.1 4a2.1 2.1 0 1 1-4.2 0a2.1 2.1 0 1 1 4.2 0z'),
      s('M11.2 5.8L5.5 21.25M12.8 5.8l5.7 15.45'),
    ],
  },
  art: {
    title: 'Art',
    why: 'A brush laying down paint: paintings, drawings and made things.',
    parts: [
      s('M21 3L11.6 12.4'),
      h('M10.15 11.05l2.8 2.8'),
      s('M9.9 11.9c-2.7.2-4.2 2-4.5 4.3c-.2 1.8-1 3.2-2.65 4.3c3.6.7 7.3-.2 8.8-2.5c1-1.5 1-3.1-.2-4.6z'),
      h('M6.6 17.6c.3-1.1 1-1.9 2-2.3', true),
    ],
  },
  photo: {
    title: 'Photo',
    why: 'A camera.',
    parts: [
      s('M3 8.25h4l1.6-2.5h6.8l1.6 2.5h4v11.5H3z'),
      s('M15.9 13.75a3.9 3.9 0 1 1-7.8 0a3.9 3.9 0 1 1 7.8 0z'),
      h('M10.2 12.9a2 2 0 0 1 1.7-1.25', true),
      h('M18.2 10.75h.8', true),
    ],
  },
  video: {
    title: 'Video',
    why: 'A film frame with a play mark.',
    parts: [
      s('M3 5.75h18v12.5H3z'),
      f('M10.1 9.2v5.6l4.8-2.8z'),
      h('M3 8.25h18M3 15.75h18M6 5.75v2.5M9.5 5.75v2.5M14.5 5.75v2.5M18 5.75v2.5M6 15.75v2.5M9.5 15.75v2.5M14.5 15.75v2.5M18 15.75v2.5', true),
    ],
  },
  sketch: {
    title: 'Sketch',
    why: 'A pencil trailing a loose line: work still being drawn out.',
    parts: [
      s('M4.5 19.5l1-4L16 5a2.1 2.1 0 0 1 3 3L8.5 18.5z'),
      h('M5.5 15.5l3 3'),
      h('M14 7l3 3', true),
      h('M3 22c2.5-.9 5.5-.4 7.5-.9s3.5-1.3 5-1.1', true),
    ],
  },
  audio: {
    title: 'Audio',
    why: 'A speaker sounding: something to hear.',
    parts: [
      s('M3.25 9.5h3.25l5.75-4.75v14.5L6.5 14.5H3.25z'),
      s('M15.4 9a4.25 4.25 0 0 1 0 6'),
      h('M18.1 6.3a8 8 0 0 1 0 11.4'),
    ],
  },
  writing: {
    title: 'Writing',
    why: 'A pen nib: words written out.',
    parts: [
      s('M7.5 3.5h9l.8 7.5c-.4 3.6-2.6 7-5.3 10.5c-2.7-3.5-4.9-6.9-5.3-10.5z'),
      h('M12 20.9v-7.5'),
      h('M13.4 12a1.4 1.4 0 1 1-2.8 0a1.4 1.4 0 1 1 2.8 0z'),
      h('M9.4 6.4h5.2', true),
    ],
  },
  note: {
    title: 'Margin note',
    why: 'A written page with a pen at its margin: a note left beside the work.',
    parts: [
      s('M3.5 3.5h10v17h-10z'),
      h('M6 8h5M6 11h5M6 14h3'),
      h('M6 17h4', true),
      s('M20.5 3.5l-3.6 11.6'),
      f('M16.2 14.6l1.9.6-1.6 3.3z'),
    ],
  },
  experiment: {
    title: 'Experiment',
    why: 'A bubbling flask: something being tried out.',
    parts: [
      s('M9.25 3h5.5M10.4 3v6.3L4.9 19.2A1.5 1.5 0 0 0 6.2 21.5h11.6a1.5 1.5 0 0 0 1.3-2.3L13.6 9.3V3'),
      h('M7.3 15h9.4'),
      f('M10.4 18a.95.95 0 1 1-1.9 0a.95.95 0 1 1 1.9 0zM14.6 17.6a.75.75 0 1 1-1.5 0a.75.75 0 1 1 1.5 0z', true),
      h('M12.7 12.6a.6.6 0 1 1-1.2 0a.6.6 0 1 1 1.2 0z', true),
    ],
  },
  life: {
    title: 'Life',
    why: 'A sprig in leaf: the living days around the work.',
    parts: [
      s('M12 21.5V9.5'),
      s('M12 14.25c-4.4 0-6.9-2.5-6.9-6.4c4.4 0 6.9 2.5 6.9 6.4z'),
      s('M12 10.6c0-3.8 2.3-6.5 6.4-6.5c0 3.8-2.3 6.5-6.4 6.5z'),
      h('M12 14.25L7.6 9.8M12 10.6l3.9-3.9', true),
      h('M8 21.5h8', true),
    ],
  },
} satisfies Record<string, IconDef>;

export type IconName = keyof typeof ICONS;
