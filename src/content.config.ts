import { defineCollection, z } from 'astro:content';
import { docsSchema } from '@astrojs/starlight/schema';

export const collections = {
  docs: defineCollection({ schema: docsSchema() }),
  news: defineCollection({
    type: 'data',
    schema: z.object({
      items: z.array(z.object({
        date: z.string(),
        content: z.string(),
      }))
    })
  }),
};