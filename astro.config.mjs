// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import { ion } from 'starlight-ion-theme';

// https://astro.build/config
export default defineConfig({
  integrations: [
    starlight({
      title: 'OSIWeb.org',
      description: 'Repository for Ohio Scientific documentation and community knowledge',
      plugins: [ion()],
      sidebar: [
        {
          label: 'Welcome',
          link: '/',
        },
        {
          label: 'News',
          link: '/news',
        },
        {
          label: 'Forum',
          link: 'https://osiweb.org/forum',
          attrs: { target: '_blank' },
        },
        {
          label: 'Hardware',
          autogenerate: { directory: 'hardware' },
        },
        {
          label: 'Software',
          autogenerate: { directory: 'software' },
        },
        {
          label: 'Manuals',
          autogenerate: { directory: 'manuals' },
        },
        {
          label: 'Books',
          autogenerate: { directory: 'books' },
        },
        {
          label: 'Journals',
          autogenerate: { directory: 'journals' },
        },
        {
          label: 'Ads & Catalogs',
          autogenerate: { directory: 'ads-catalogs' },
        },
        {
          label: 'Tips & Tricks',
          autogenerate: { directory: 'tips-tricks' },
        },
        {
          label: 'Links & Resources',
          autogenerate: { directory: 'links-resources' },
        }
      ]
    })
  ]
});
