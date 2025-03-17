import TextCopyBlock from "@/components/TextCopyBlock";
import { Script } from "@/lib/types";
import { AlertColors } from "@/config/siteConfig";
import { AlertCircle, NotepadText } from "lucide-react";
import { cn } from "@/lib/utils";

export default function Description({ item }: { item: Script }) {
  return (
    <div className="p-2">
      <h2 className="mb-2 max-w-prose text-lg font-semibold">Description</h2>
      <p className={cn(
                "inline-flex items-center gap-2 rounded-lg border p-2 pl-4 text-lg pr-4",
                AlertColors["warning"],
              )} >
        <AlertCircle className="h-4 min-h-4 w-4 min-w-4" />
              <span>Only use for testing, not in production!</span>
      </p>
      <p className="text-sm text-muted-foreground pt-4">
        {TextCopyBlock(item.description)}
      </p>
    </div>
  );
}
